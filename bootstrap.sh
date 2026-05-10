#!/bin/bash
set -eo pipefail

# 1. Install K3s (Host Network is used by default)
if ! command -v k3s &> /dev/null; then
    echo "Installing K3s..."
    curl -sfL https://get.k3s.io | sh -
    sudo chmod 644 /etc/rancher/k3s/k3s.yaml
    
    # Persist KUBECONFIG for the current user
    if ! grep -q "KUBECONFIG" ~/.bashrc; then
        echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc
    fi
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 2. Install ArgoCD
echo "Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3. Wait for ArgoCD to be ready
echo "Waiting for ArgoCD..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

# 4. Configure ArgoCD (Enable Helm in Kustomize)
kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data":{"kustomize.buildOptions":"--enable-helm"}}'

# 5. Bootstrap applications
echo "Applying App-of-Apps..."
kubectl apply -f https://raw.githubusercontent.com/daigo-suhara/capt-cluster/master/argocd/app-of-apps.yaml

echo "Bootstrap complete!"
