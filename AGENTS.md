# Repository tooling

Development tools for this repository are managed in `devbox.json`. Run them from
the Devbox environment rather than relying on tools installed on the host.

Installed tools:

- `helm` — provided by the `kubernetes-helm` package
- `kubectl`
- `kustomize`
- `just`

Start an interactive environment with `devbox shell`, or run a command directly
with `devbox run -- <command>` (for example, `devbox run -- kustomize build
applications/cert-manager/overlays/service`).
