kustomize := env("KUSTOMIZE", "kustomize")
apps_dir := env("APPS_DIR", "applications")
helm := env("HELM", "helm")

# Render all application Kustomizations and report failures
[default]
all: check-apps

# Show available recipes
help:
    @just --list

# List all discovered kustomization directories
list-kustomizations:
    #!/usr/bin/env sh
    find "{{ apps_dir }}" -type f -name kustomization.yaml -exec dirname {} \; | sort

# Generate a new kustomization directory structure under applications/
template name="":
    #!/usr/bin/env sh
    set -e
    app_name="{{ name }}"
    if [ -z "$app_name" ]; then
        printf "Enter the name of the new kustomization (e.g., my-app): "
        read -r app_name
    fi
    if [ -z "$app_name" ]; then
        echo "No name provided. Aborting."
        exit 1
    fi
    dir="{{ apps_dir }}/$app_name"
    if [ -d "$dir" ]; then
        echo "Directory $dir already exists. Aborting."
        exit 1
    fi
    mkdir -p "$dir"
    mkdir -p "$dir/base"
    mkdir -p "$dir/base/resources"
    mkdir -p "$dir/overlays"
    touch "$dir/base/kustomization.yaml"

# Vendor or refresh an upstream Helm chart in the repository
vendor-helm-chart repository chart version destination:
    HELM="{{ helm }}" scripts/vendor-helm-chart.sh "{{ repository }}" "{{ chart }}" "{{ version }}" "{{ destination }}"

# Render all Kustomizations under applications/
render-apps:
    #!/usr/bin/env sh
    set -e
    dirs=$(find "{{ apps_dir }}" -type f -name kustomization.yaml -exec dirname {} \; 2>/dev/null | sort)
    if [ -z "$dirs" ]; then
        echo "No kustomizations found under {{ apps_dir }}/"
        exit 0
    fi
    for d in $dirs; do
        echo "==> Rendering $d"
        "{{ kustomize }}" build "$d" >/dev/null
    done
    echo "All kustomizations rendered successfully."

# Render every vendored top-level Helm chart
check-helm-charts:
    #!/usr/bin/env sh
    set -eu
    if ! command -v "{{ helm }}" >/dev/null 2>&1; then
        echo "Error: {{ helm }} is not installed or not in PATH."
        exit 1
    fi
    render_chart() {
        case "$1" in
            */observability/charts/loki)
                "{{ helm }}" template chart-check "$1" \
                    --set loki.storage.bucketNames.chunks=chart-check \
                    --set loki.storage.bucketNames.ruler=chart-check \
                    --set loki.storage.bucketNames.admin=chart-check \
                    --set loki.useTestSchema=true
                ;;
            */sonarqube/charts/sonarqube)
                "{{ helm }}" template chart-check "$1" \
                    --set monitoringPasscodeSecretName=chart-check \
                    --set monitoringPasscodeSecretKey=key \
                    --set community.enabled=true
                ;;
            *)
                "{{ helm }}" template chart-check "$1"
                ;;
        esac
    }
    found=0
    failed=0
    for app in "{{ apps_dir }}"/*; do
        [ -d "$app/charts" ] || continue
        for chart in "$app"/charts/*; do
            [ -f "$chart/Chart.yaml" ] || continue
            found=1
            if render_chart "$chart" >/dev/null; then
                echo "[OK]   $chart"
            else
                echo "[FAIL] $chart"
                failed=1
            fi
        done
    done
    if [ "$found" -eq 0 ]; then
        echo "No vendored Helm charts found under {{ apps_dir }}/"
        exit 0
    fi
    if [ "$failed" -ne 0 ]; then
        echo "One or more Helm charts failed to render."
        exit 1
    fi
    echo "All vendored Helm charts rendered successfully."

# Render all kustomizations and print concise OK/FAIL summary
check-apps:
    #!/usr/bin/env sh
    set -e
    if ! command -v "{{ kustomize }}" >/dev/null 2>&1; then
        echo "Error: {{ kustomize }} is not installed or not in PATH."
        exit 1
    fi
    dirs=$(find "{{ apps_dir }}" -type f -name kustomization.yaml -exec dirname {} \; 2>/dev/null | sort)
    if [ -z "$dirs" ]; then
        echo "No kustomizations found under {{ apps_dir }}/"
        exit 0
    fi
    failed=0
    for d in $dirs; do
        if "{{ kustomize }}" build "$d" >/dev/null; then
            echo "[OK]   $d"
        else
            echo "[FAIL] $d"
            failed=1
        fi
    done
    if [ $failed -ne 0 ]; then
        echo "One or more kustomizations failed."
        exit 1
    fi
    echo "All kustomizations passed."
