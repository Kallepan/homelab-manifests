# Homelab Kubernetes GitOps Configuration

This repository contains Kubernetes manifests and Argo CD `Application` resources for a homelab cluster. Most application releases are installed from Helm charts by Argo CD; other directories contain Kubernetes resources or operator subscriptions. Kustomize bases hold shared configuration and overlays hold cluster-specific changes.

## Repository layout

```text
applications/
  <app>/
    charts/<chart>/          # Vendored upstream Helm chart, when applicable
    base/
      kustomization.yaml
      resources/             # Kubernetes resources and/or Argo CD Applications
    overlays/
      service/
        kustomization.yaml  # references ../../base and applies local patches
```

The active overlay in this repository is generally `service`. `_deprecated/` contains retired configurations and is not part of the active application tree.

Each `applications/<app>/base/resources/application.yaml` (where present) defines an Argo CD `Application` for the release. Some apps instead contain resources directly. The `argocd` application manages the Argo CD Helm release itself.

### Vendored Helm charts

Argo CD Helm releases are vendored below the owning application in
`applications/<app>/charts/<chart>/`. The chart's `Chart.yaml` records its exact
version and upstream repository; templates, defaults, CRDs, and packaged
dependencies are tracked alongside it. Applications render these checked-in
chart directories from this Git repository rather than resolving versions from
an upstream Helm repository.

Renovate monitors the upstream versions recorded in each vendored chart and
refreshes the complete chart directory in its update branch, including
templates, defaults, CRDs, and packaged dependencies. The refresh task runs
with Helm from the full Renovate image and is allowlisted in the Renovate
workflow.

To refresh a chart manually, pull the desired version into its existing
directory. `VERSION` can be an exact version or a Helm semver constraint; for
OCI charts, pass the registry URL with the `oci://` prefix. Quote wildcard
constraints to prevent shell expansion:

```sh
devbox run -- just vendor-helm-chart \
  https://charts.jetstack.io cert-manager v1.21.2 \
  applications/cert-manager/charts/cert-manager
```

The GitLab chart is an exception: it is fetched and rendered by the GitLab
Operator from the version in `applications/gitlab/base/resources/gitlab.yaml`,
rather than by an Argo CD Helm source.

### Bootstrap and application discovery

There is no `ApplicationSet`, `cluster-config/`, or root app-of-apps manifest in this repository. Argo CD therefore needs an existing bootstrap/root `Application` (configured outside this repository) that discovers the desired `applications/*/overlays/<cluster>` directories. Check that bootstrap source before expecting newly added overlays to deploy. Keep overlay directory names aligned with the cluster names used by that source.

## Development

Tools are pinned in `devbox.json`; run them through Devbox:

```sh
devbox run -- just check-apps
devbox run -- just check-helm-charts
devbox run -- prek run --all-files
```

`just check-apps` renders each discovered Kustomize directory under `applications/`; `just check-helm-charts` renders every vendored chart with Helm. Some Kustomizations use pinned upstream Git sources and need network access. `devbox run -- test` runs both render checks and the pre-commit hooks.

To render one overlay:

```sh
devbox run -- kustomize build applications/<app>/overlays/service
```

## Adding an application

1. Add the app's shared resources beneath `applications/<app>/base/resources/` and list them in `base/kustomization.yaml`.
2. If Argo CD should manage a Helm release, add an `argoproj.io/v1alpha1` `Application` resource using the conventions of nearby apps. For plain Kubernetes resources, include them directly.
3. Add an overlay for each target cluster, starting with a reference to `../../base`; put cluster-specific patches in that overlay.
4. Render the base and overlay using the commands above, then verify the external bootstrap/root app includes the overlay path.

Example overlay:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
```

## Configuration practices

- Put credentials in External Secrets resources or another secret manager; do not commit secret values in manifests.
- Pin container images and chart versions instead of using floating tags or broad revisions where possible.
- Use Kustomize overlays for cluster-specific differences rather than duplicating an application's base.
- Keep TLS verification enabled. For internal services, configure the required CA trust rather than bypassing certificate verification.
- Review Argo CD destination namespaces, sync policies, and pruning behavior before enabling automated reconciliation.
- Make cluster changes through the repository's GitOps workflow. Use `kubectl` only for read-only inspection and troubleshooting.

## YAML hooks

Install the repository hooks once:

```sh
devbox run -- prek install
```

Run them manually:

```sh
devbox run -- prek run --all-files
```
