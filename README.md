# Homelab Kubernetes GitOps Configuration

This repository contains the GitOps configuration for my homelab Kubernetes clusters using ArgoCD ApplicationSets for multi-cluster management.

## 📁 Repository Structure

```bash
homelab-manifests/
├── apps/
│   ├── management/          # Applications for management clusters (type=management)
│   │   └── prometheus/      # Example: Monitoring stack
│   ├── service/             # Applications for service clusters (type=service)
│   │   └── my-app/          # Example: User-facing application
│   └── shared/              # Applications deployed to ALL clusters
│       └── cert-manager/    # Example: Certificate management
└── applicationsets/         # ApplicationSet definitions
    ├── management-apps.yaml # Targets clusters with type=management
    ├── service-apps.yaml    # Targets clusters with type=service
    └── shared-apps.yaml     # Targets all clusters
```

## 🎯 How It Works

This repository uses **ArgoCD ApplicationSets** with **cluster label selectors** to automatically deploy applications to the correct cluster types.

### Cluster Labels

Your clusters should have labels applied in ArgoCD:

- **Management cluster**: `type=management`
- **Service cluster**: `type=service`

### ApplicationSet Targeting

Each ApplicationSet uses the `selector` field to target specific cluster types:

**Management Apps** (`apps/management/*`)

- Only deployed to clusters with `type=management`
- Examples: Prometheus, Grafana, ArgoCD, Vault

**Service Apps** (`apps/service/*`)

- Only deployed to clusters with `type=service`
- Examples: User applications, APIs, web services

**Shared Apps** (`apps/shared/*`)

- Deployed to ALL clusters regardless of labels
- Examples: cert-manager, ingress-nginx, monitoring agents

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

# Or for service clusters
kubectl label secret -n argocd CLUSTER_SECRET_NAME type=service
```

### 2. Update Repository URL

Edit the ApplicationSet files and replace `YOUR_USERNAME` with your actual GitHub username/organization:

```bash
# Find and replace in all ApplicationSet files
sed -i '' 's/YOUR_USERNAME/your-actual-username/g' applicationsets/*.yaml
```

### 3. Apply ApplicationSets

Apply the ApplicationSets to your ArgoCD instance:

```bash
# Apply all ApplicationSets
kubectl apply -f applicationsets/

# Or apply individually
kubectl apply -f applicationsets/management-apps.yaml
kubectl apply -f applicationsets/service-apps.yaml
kubectl apply -f applicationsets/shared-apps.yaml
```

### 4. Add New Applications

To add a new application, simply create a new directory in the appropriate folder:

**For a management-only app:**

```bash
mkdir -p apps/management/my-new-app
# Add your manifests to apps/management/my-new-app/
```

**For a service-only app:**

```bash
mkdir -p apps/service/my-new-app
# Add your manifests to apps/service/my-new-app/
```

**For an app on all clusters:**

```bash
mkdir -p apps/shared/my-new-app
# Add your manifests to apps/shared/my-new-app/
```

The ApplicationSet will automatically detect the new directory and create an ArgoCD Application for each matching cluster!

## 🔍 Verification

Check that ApplicationSets are creating the expected Applications:

```bash
# List all applications created by ApplicationSets
kubectl get applications -n argocd

# Check ApplicationSet status
kubectl get applicationsets -n argocd

# View details of a specific ApplicationSet
kubectl describe applicationset management-apps -n argocd
```

## 🛠️ Advanced Configuration

### Using Multiple Labels

You can use multiple labels for more granular targeting:

```yaml
spec:
  generators:
    - git:
        # ... git config ...
      selector:
        matchLabels:
          type: service
          region: us-west
```

### Using matchExpressions

For more complex label selection:

```yaml
spec:
  generators:
    - git:
        # ... git config ...
      selector:
        matchExpressions:
          - key: type
            operator: In
            values:
              - service
              - edge
```

### Per-Application Customization

You can override settings per application by adding a `.argocd-source.yaml` file:

```yaml
# apps/management/prometheus/.argocd-source.yaml
helm:
  values: |
    replica: 2
    retention: 30d
```

## 📝 Best Practices

1. **One directory per application** - Each app should have its own directory
2. **Use consistent naming** - Name directories with lowercase and hyphens
3. **Namespace per app** - Create namespaces in your manifests (with `CreateNamespace=true`)
4. **Commit atomically** - Commit each app addition/change separately for clearer history
5. **Test in dev first** - Use a `dev` cluster label to test changes before production

## 🔐 Security Considerations

- Keep sensitive values in Kubernetes Secrets or use tools like Sealed Secrets
- Different clusters may need different configurations (use Kustomize overlays)
- Regularly review what's deployed where with `kubectl get applications -n argocd`

## 🆘 Troubleshooting

**Applications not appearing?**

- Check that your directory structure matches `apps/{type}/*`
- Verify cluster labels match the ApplicationSet selectors
- Check ApplicationSet status: `kubectl describe applicationset <name> -n argocd`

**Applications in wrong clusters?**

- Verify cluster labels: `kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster`
- Check the ApplicationSet selector configuration

**Changes not syncing?**

- ApplicationSets check the Git repository every 3 minutes by default
- Force refresh: `kubectl patch applicationset <name> -n argocd -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"true"}}}' --type merge`
