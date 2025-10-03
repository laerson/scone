#!/bin/bash
set -euo pipefail

source /scone-registry.env

mkdir -p ~/.kube
if [[ -f /kubeconfig ]]; then
  cp /kubeconfig ~/.kube/config
else
  APISERVER="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"
  TOKEN="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
  CA="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
  NS="$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)"
  kubectl config set-cluster in-cluster --server="$APISERVER" --certificate-authority="$CA" --embed-certs=true
  kubectl config set-credentials sa --token="$TOKEN"
  kubectl config set-context in-cluster --cluster=in-cluster --user=sa --namespace="$NS"
  kubectl config use-context in-cluster
fi

cd "$HOME"
git clone https://github.com/scontain/scone.git || true

~/scone/scripts/prerequisite_check.sh

alias k=kubectl
exec "$@"
