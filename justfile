kustomize := env("KUSTOMIZE", "kustomize")
apps_dir := env("APPS_DIR", "apps")

# Run check-apps and render-apps
[default]
all: check-apps render-apps

# Show available recipes
help:
    @just --list

# List all discovered kustomization directories
list-kustomizations:
    #!/usr/bin/env sh
    find "{{ apps_dir }}" -type f -name kustomization.yaml -exec dirname {} \; | sort

# Generate a new kustomization directory structure under apps/
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

# Render all kustomizations under apps/
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
        if "{{ kustomize }}" build "$d" >/dev/null 2>&1; then
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
