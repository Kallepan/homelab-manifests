# Homelab Kubernetes GitOps Configuration

This repository contains the GitOps configuration for my homelab Kubernetes clusters using ArgoCD ApplicationSets for multi-cluster management with Kustomize overlays.

## 📁 Repository Structure

```no-highlight
homelab-manifests/
├── apps/
│   ├── cert-manager/              # Application name
│   │   ├── base/                  # Base manifests
│   │   │   ├── kustomization.yaml
│   │   │   └── resources/
│   │   │       ├── namespace.yaml
│   │   │       └── application.yaml
│   │   └── overlays/              # Cluster-specific overlays
│   │       ├── management/        # Overlay for "management" cluster
│   │       │   └── kustomization.yaml
│   │       └── service/           # Overlay for "service" cluster
│   │           └── kustomization.yaml
│   ├── prometheus/                # Another app
│   │   ├── base/
│   │   └── overlays/
│   │       └── management/
│   └── my-app/                    # Another app
│       ├── base/
│       └── overlays/
│           └── service/
└── cluster-config/
    └── all-apps.yaml              # Single ApplicationSet for all apps
```

## 🎯 How It Works

This repository uses **ArgoCD ApplicationSets** with **Kustomize overlays** to deploy applications to clusters based on cluster names.

### Architecture

The setup uses a **single ApplicationSet** with a **matrix generator** that combines:

1. **Cluster Generator**: Discovers all clusters with `type=management` or `type=workload` labels
2. **Git Generator**: Finds overlay directories matching cluster names: `apps/*/overlays/{{.name}}`

This automatically deploys the right applications to the right clusters based on which overlays exist.

### Directory Structure Pattern

Each application follows the Kustomize pattern:

```no-highlight
apps/{app-name}/
├── base/                       # Common resources for all clusters
│   ├── kustomization.yaml     # Base Kustomize config
│   └── resources/             # Your Kubernetes manifests
│       ├── namespace.yaml
│       └── deployment.yaml
└── overlays/                   # Cluster-specific customizations
    ├── {cluster-name-1}/
    │   └── kustomization.yaml # References ../../base + customizations
    └── {cluster-name-2}/
        └── kustomization.yaml
```

### Cluster Labels

Your clusters should have labels applied in ArgoCD:

- **Management clusters**: `type=management` (cluster name example: `management`)
- **Workload clusters**: `type=workload` (cluster name example: `service`, `production`)

### Application Deployment Logic

The ApplicationSet matches **app overlays with cluster names**:

- If `apps/cert-manager/overlays/management/` exists → deploys to cluster named `management`
- If `apps/cert-manager/overlays/service/` exists → deploys to cluster named `service`
- If `apps/my-app/overlays/production/` exists → deploys to cluster named `production`

**Key Point**: The overlay directory name must match the cluster name exactly (case-sensitive).

## 🚀 Usage

### 1. Verify Cluster Labels

First, ensure your clusters are labeled correctly in ArgoCD:

```bash
# List all clusters and their labels
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster -o json | \
  jq -r '.items[] | "\(.metadata.name): \(.metadata.labels)"'
```

If you need to add labels to a cluster:

```bash
# Add label to a cluster secret
kubectl label secret -n argocd CLUSTER_SECRET_NAME type=management

# Or for workload clusters
kubectl label secret -n argocd CLUSTER_SECRET_NAME type=workload
```

### 2. Apply the ApplicationSet

Apply the ApplicationSet to your ArgoCD instance:

```bash
kubectl apply -f cluster-config/all-apps.yaml
```

### 3. Add a New Application

To add a new application:

#### Step 1: Create the base structure

```bash
mkdir -p apps/my-new-app/base/resources
```

#### Step 2: Add your Kubernetes manifests

```bash
# Create namespace
cat > apps/my-new-app/base/resources/namespace.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: my-new-app
EOF

# Create deployment
cat > apps/my-new-app/base/resources/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-new-app
  namespace: my-new-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-new-app
  template:
    metadata:
      labels:
        app: my-new-app
    spec:
      containers:
      - name: app
        image: nginx:latest
        ports:
        - containerPort: 80
EOF
```

#### Step 3: Create the base kustomization.yaml

```bash
cat > apps/my-new-app/base/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - resources/namespace.yaml
  - resources/deployment.yaml
EOF
```

#### Step 4: Create overlay for your target cluster (must match cluster name exactly)

```bash
mkdir -p apps/my-new-app/overlays/management

cat > apps/my-new-app/overlays/management/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

# Add cluster-specific customizations here
EOF
```

The ApplicationSet will automatically detect the new overlay and deploy the app to the `management` cluster!

### 4. Deploy to Additional Clusters

To deploy an existing app to another cluster, just create a new overlay with the cluster's name:

```bash
# Deploy cert-manager to a cluster named "production"
mkdir -p apps/cert-manager/overlays/production

cat > apps/cert-manager/overlays/production/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

# Optional: add cluster-specific patches
patches:
  - patch: |-
      - op: replace
        path: /spec/replicas
        value: 3
    target:
      kind: Deployment
      name: cert-manager
EOF
```

## 🔍 Verification

Check that the ApplicationSet is creating the expected Applications:

```bash
# List all applications created by the ApplicationSet
kubectl get applications -n argocd

# Check ApplicationSet status
kubectl get applicationsets -n argocd

# View details of the ApplicationSet
kubectl describe applicationset homelab-apps -n argocd
```

## 🛠️ Advanced Configuration

### Kustomize Patches

Use Kustomize patches in overlays for cluster-specific customizations:

```yaml
# apps/my-app/overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

# Change replica count
replicas:
  - name: my-app
    count: 5

# Add labels
commonLabels:
  environment: production
  cluster: production

# Patch resources
patches:
  - patch: |-
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value:
          name: CLUSTER_NAME
          value: production
    target:
      kind: Deployment
      name: my-app
```

### Using ConfigMaps per Cluster

Create cluster-specific ConfigMaps in overlays:

```yaml
# apps/my-app/overlays/production/config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-app-config
  namespace: my-app
data:
  cluster: production
  region: us-west
  replicas: "5"
```

```yaml
# apps/my-app/overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base
  - config.yaml
```

### Organizing Apps

All apps are at the root level of `apps/`. You can organize by naming convention:

- `apps/cert-manager/` - Common utilities
- `apps/prometheus/` - Infrastructure monitoring  
- `apps/my-web-app/` - Business applications

Control which clusters get which apps by creating overlays only for the desired clusters.

## 📝 Best Practices

1. **Use base for common config** - Keep shared manifests in `base/`, cluster differences in `overlays/`
2. **One overlay per cluster** - Each cluster gets its own overlay directory named exactly as the cluster
3. **Consistent naming** - Use lowercase with hyphens for app and cluster names
4. **Namespace per app** - Create namespaces in your base manifests (ApplicationSet uses `CreateNamespace=true`)
5. **Minimal overlays** - Start with empty overlays that just reference the base, add customizations only when needed
6. **Test with kustomize build** - Before committing, test with `kubectl kustomize build apps/{app}/overlays/{cluster}/`
