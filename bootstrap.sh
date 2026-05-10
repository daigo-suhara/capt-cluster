#!/bin/bash
set -eo pipefail

# 1. Install MicroK8s
if ! command -v microk8s &> /dev/null; then
    echo "Installing MicroK8s..."
    sudo snap install microk8s --classic
    sudo usermod -a -G microk8s $USER
    sudo chown -f -R $USER ~/.kube
    
    echo "Waiting for MicroK8s to be ready..."
    sudo microk8s status --wait-ready
    
    echo "Enabling addons..."
    sudo microk8s enable dns storage
fi

# Alias kubectl
if ! command -v kubectl &> /dev/null; then
    sudo snap alias microk8s.kubectl kubectl
fi

# 2. Install ArgoCD
echo "Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3. Wait for ArgoCD to be ready
echo "Waiting for ArgoCD..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

# 4. Configure ArgoCD (Enable Helm in Kustomize)
kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data":{"kustomize.buildOptions":"--enable-helm"}}'

# 5. Bootstrap applications
echo "Applying App-of-Apps..."
kubectl apply -f https://raw.githubusercontent.com/daigo-suhara/capt-cluster/master/argocd/app-of-apps.yaml

echo "Bootstrap complete!"
