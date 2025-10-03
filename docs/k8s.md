# Deploying SCONE CLI Image on Kubernetes

## Prerequisites

- kubectl
- access to a Kubernetes cluster with confidential nodes

## Deployment

1. Build and Push the image

    ```bash
    docker build -t <registry>/<username>/repository>:<tag> .
    docker push <registry>/<username>/<repository>:<tag>
    ```

2. Create Namespace and Secrets

    ```bash
    kubectl create ns scone-tools
   
    kubectl -n scone-tools create secret docker-registry scone-registry \
      --docker-server=registry.scontain.com \
      --docker-username="SCONE_REGISTRY_USERNAME" \
      --docker-password="SCONE_REGISTRY_PASSWORD" \
   
   kubectl -n scone-tools create secret generic scone-registry-env \
    --from-file=./scone-registry.env=./scone-registry.env
   
   kubectl -n scone-tools create secret docker-registry app-regcred \
    --docker-server=<registry> \
    --docker-username="<username>" \
    --docker-password="<a PAT with read:packages>"
   ```
   
3. Add RBAC to the namespace

    ```bash
    kubectl apply -f ./k8s/rbac.yaml
    ```
   
4. Deploy the SCONE CLI
    - Remember to change the image name in the pod.yaml file for the one you pushed in step 1

    ```bash
    kubectl apply -f ./k8s/pod.yaml
    ```

5. Watch the logs of the pod

    ```bash
   kubectl -n scone-tools logs -f scone-toolbox
    ```
   
6. Drop into the shell when it's ready

    ```bash
   kubectl -n scone-tools exec -it scone-toolbox -- bash
   ```
   
7. Run the SCONE CLI

    ```bash
    scone --help
    ```
