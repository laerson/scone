#!/usr/bin/env bash
set -euo pipefail

LILAC='\033[1;35m'; RESET='\033[0m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'

printf "${LILAC}"
cat <<'EOHDR'
# SCONE CLI

You can run the ['scone' CLI](https://sconedocs.github.io/CAS_cli/) on your **host machine**, within a **virtual machine (VM)**, or inside a **container**. Running in a container is portable but can be slower; installing on your dev machine is fastest.

## Caveat When Running Inside a Container

There are two versions of the 'scone' CLI:
- a **native version** (cannot run inside an enclave)
- the **default version** (designed to run inside an enclave)

If you do not have production TEEs, set `SCONE_PRODUCTION=0` to run in simulation, e.g.:
`SCONE_PRODUCTION=0 scone --help`.

We'll install the CLI on Debian/Ubuntu via packages contained in an image.

EOHDR
printf "${RESET}"

# --- Discover version ---
VERSION="$(curl -sSL https://raw.githubusercontent.com/scontain/scone/refs/heads/main/stable.txt)"
echo "The lastest stable version of SCONE is $VERSION"

printf "${LILAC}"
cat <<'EOVERIFY'
The SCONE CLI is available as Debian packages inside a container image.
We verify that image with cosign, then extract the packages (without Docker).

EOVERIFY
printf "${RESET}"

# --- Cosign public key for scone.cloud images ---
create_cosign_verification_key() {
  export cosign_public_key_file="$(mktemp).pub"
  cat > "$cosign_public_key_file" <<'EOKEY'
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAErLf0HT8xZlLaoX5jNN8aVL1Yrs+P
wS7K6tXeRlWLlUX1GeEtTdcuhZMKb5VUNaWEJW2ZU0YIF91D93dCZbUYpw==
-----END PUBLIC KEY-----
EOKEY
}

verify_image() {
  local image_name="${1:-}"
  if [[ -z "$image_name" ]]; then
    echo "Image name is empty"; exit 1
  fi
  echo "Verifying the signature of image '$image_name'"
  : "${cosign_public_key_file:=}"; [[ -z "${cosign_public_key_file}" ]] && create_cosign_verification_key
  # cosign talks to the registry directly; no Docker daemon required
  cosign verify --key "$cosign_public_key_file" "$image_name" >/dev/null 2>&1 \
    || { echo -e "${RED}Failed to verify signature of '$image_name'. Ensure 'cosign version' >= 2.0.0.${RESET}"; exit 1; }
  echo " - verification was successful"
}

# --- K8s-based extractor (no Docker) ---
extract_packages_via_k8s() {
  local image="$1"
  local ns="${NAMESPACE:-$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace 2>/dev/null || echo default)}"
  local sa="${SERVICE_ACCOUNT:-scone-runner}"
  local pullsecret="${SCONE_PULL_SECRET:-scone-registry}"
  local name="extract-$(echo "$image" | tr '/:.' '-' | cut -c1-55)"
  local workdir="${WORKDIR:-/tmp/sconecli_pkgs}"

  mkdir -p "$workdir"

  # --- all LOGGING goes to stderr ---
  echo "Creating ephemeral pod '$name' in namespace '$ns' to extract /packages ..." >&2

  kubectl -n "$ns" delete pod "$name" --ignore-not-found --now >/dev/null 2>&1 || true

  cat <<YAML | kubectl apply -n "$ns" -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: $name
  labels: { app: sconecli-extract }
spec:
  serviceAccountName: $sa
  restartPolicy: Never
  imagePullSecrets:
  - name: $pullsecret
  containers:
  - name: target
    image: "$image"
    imagePullPolicy: Always
    command: ["sh","-lc","sleep 600"]
YAML

  kubectl -n "$ns" wait --for=condition=ContainersReady pod/"$name" --timeout=300s >/dev/null

  # sanity check and then copy; specify the container explicitly (-c target)
  kubectl -n "$ns" exec "$name" -c target -- ls -la /packages >/dev/null 2>&1 \
    || { echo "ERROR: /packages not found inside image $image" >&2; kubectl -n "$ns" delete pod "$name" --now >/dev/null 2>&1 || true; return 1; }

  echo "Copying packages from pod ..." >&2
  kubectl -n "$ns" cp -c target "$name:/packages" "$workdir/packages" >/dev/null

  kubectl -n "$ns" delete pod "$name" --now --ignore-not-found >/dev/null 2>&1 || true

  echo "Packages staged at: $workdir/packages" >&2

  # --- ONLY the path is printed to stdout ---
  echo "$workdir"
}

# --- Main flow ---
REPO="registry.scontain.com/scone.cloud"
IMAGE="scone-deb-pkgs"
PKG_IMG="$REPO/$IMAGE:$VERSION"

verify_image "$PKG_IMG"

printf "${LILAC}"
cat <<'EOCOPY'
After successful verification, we extract the Debian packages from the image
(via an ephemeral Kubernetes pod) and install them locally.
EOCOPY
printf "${RESET}"

# Extract packages (no Docker)
STAGE_DIR="$(extract_packages_via_k8s "$PKG_IMG")"
PKG_DIR="$STAGE_DIR/packages"
dpkg -i "$PKG_DIR"/scone-common_amd64.deb \
       "$PKG_DIR"/scone-libc_amd64.deb \
       "$PKG_DIR"/scone-cli_amd64.deb \
       "$PKG_DIR"/k8s-scone.deb \
       "$PKG_DIR"/kubectl-scone.deb


# Cleanup staged files
rm -rf "$STAGE_DIR"

printf "${LILAC}"
cat <<'EOCHECK'
We ensure that 'kubectl-scone' plugin only exists once - otherwise 'kubectl' prints a warning:
EOCHECK
printf "${RESET}"

if [[ -e /usr/bin/kubectl-scone && -e /bin/kubectl-scone ]] ; then
  P1=$(realpath /usr/bin/kubectl-scone )
  P2=$(realpath /bin/kubectl-scone )
  if [[ -n "$P1" && -n "$P2" && "$P1" != "$P2" ]]; then
    rm -f "$P2"
  fi
fi

echo "Expecting SCONE version: $VERSION"
scone --version || { echo -e "${RED}SCONE CLI not found after install${RESET}"; exit 1; }

printf "${LILAC}"
cat <<'EOFTRAIL'
This should match the latest stable version printed above.
(The minimal version is 5.10.1)

✅ All scone-related executables installed (containerd/Kubernetes mode)
EOFTRAIL
printf "${RESET}"
