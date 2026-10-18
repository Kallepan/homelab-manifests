kustomize := env("KUSTOMIZE", "kustomize")
apps_dir := env("APPS_DIR", "applications")

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

# Generate an application: just template <name> <cluster> [external_secret] [postgres]
template name="" cluster="service" external_secret="false" postgres="false":
    #!/usr/bin/env sh
    set -eu
    app_name="{{ name }}"
    if [ -z "$app_name" ]; then
        printf "Enter the application name (e.g., my-app): "
        read -r app_name
    fi
    if [ -z "$app_name" ]; then
        echo "No name provided. Aborting."
        exit 1
    fi
    cluster_name="{{ cluster }}"
    include_external_secret="{{ external_secret }}"
    include_postgres="{{ postgres }}"
    valid_label() {
        value="$1"
        case "$value" in
            ""|*[!a-z0-9-]*|-*|*-)
                return 1
                ;;
        esac
        [ "${#value}" -le 63 ]
    }
    if ! valid_label "$app_name"; then
        echo "Application name must be a lowercase DNS label (letters, numbers, hyphens; max 63 characters)."
        exit 1
    fi
    if ! valid_label "$cluster_name"; then
        echo "Cluster name must be a lowercase DNS label (letters, numbers, hyphens; max 63 characters)."
        exit 1
    fi
    case "$include_external_secret" in
        true|false) ;;
        *) echo "external_secret must be true or false."; exit 1 ;;
    esac
    case "$include_postgres" in
        true|false) ;;
        *) echo "postgres must be true or false."; exit 1 ;;
    esac
    dir="{{ apps_dir }}/$app_name"
    if [ -d "$dir" ]; then
        echo "Application directory $dir already exists. Aborting."
        exit 1
    fi
    mkdir -p "$dir/base/resources" "$dir/overlays/$cluster_name"
    cat > "$dir/base/resources/namespace.yaml" <<EOF
    apiVersion: v1
    kind: Namespace
    metadata:
      name: $app_name
      labels:
        name: $app_name
    EOF
    cat > "$dir/base/resources/application.yaml" <<EOF
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: $app_name
      namespace: argocd
      annotations:
        argocd.argoproj.io/sync-wave: "3"
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        # Replace these chart source placeholders before deployment.
        chart: $app_name
        repoURL: https://charts.example.com
        targetRevision: "REPLACE_WITH_CHART_VERSION"
        helm:
          releaseName: $app_name
          valuesObject: {}
      destination:
        server: https://kubernetes.default.svc
        namespace: $app_name
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - ServerSideApply=true
    EOF
    cat > "$dir/base/kustomization.yaml" <<EOF
    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization

    resources:
      - ./resources/namespace.yaml
      - ./resources/application.yaml
    EOF
    cat > "$dir/overlays/$cluster_name/kustomization.yaml" <<EOF
    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization

    resources:
      - ../../base
    EOF
    if [ "$include_external_secret" = "true" ]; then
        app_key=$(printf '%s' "$app_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
        cat > "$dir/base/resources/external-secret.yaml" <<EOF
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: $app_name-credentials
      namespace: $app_name
    spec:
      refreshInterval: "1h"
      secretStoreRef:
        name: openbao
        kind: ClusterSecretStore
      target:
        name: $app_name-credentials
        creationPolicy: Owner
      data:
        - secretKey: client-id
          remoteRef:
            key: services/$app_name
            property: ${app_key}_CLIENT_ID
        - secretKey: client-secret
          remoteRef:
            key: services/$app_name
            property: ${app_key}_CLIENT_SECRET
    EOF
        cat >> "$dir/base/kustomization.yaml" <<EOF
      - ./resources/external-secret.yaml
    EOF
    fi
    if [ "$include_postgres" = "true" ]; then
        app_key=$(printf '%s' "$app_name" | tr '-' '_')
        cat > "$dir/base/resources/cluster.yaml" <<EOF
    apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    metadata:
      name: $app_name-postgresql
      namespace: $app_name
    spec:
      instances: 2
      storage:
        storageClass: ceph-block
        size: 10Gi
      backup:
        barmanObjectStore:
          destinationPath: s3://pg-backups/$app_name-postgresql
          endpointURL: https://s3.storage.home.arpa
          s3Credentials:
            accessKeyId:
              name: postgres-backup-credentials
              key: ACCESS_KEY_ID
            secretAccessKey:
              name: postgres-backup-credentials
              key: ACCESS_SECRET_KEY
            region:
              name: postgres-backup-credentials
              key: REGION
          endpointCA:
            name: postgres-backup-credentials
            key: ca.crt
          wal:
            compression: gzip
            maxParallel: 2
        retentionPolicy: "30d"
      bootstrap:
        initdb:
          database: ${app_key}_db
          owner: $app_key
    EOF
        cat > "$dir/base/resources/scheduled-backup.yaml" <<EOF
    apiVersion: postgresql.cnpg.io/v1
    kind: ScheduledBackup
    metadata:
      name: $app_name-postgresql-backup
      namespace: $app_name
    spec:
      schedule: "0 0 1 * * *"
      backupOwnerReference: self
      cluster:
        name: $app_name-postgresql
    EOF
        cat > "$dir/base/resources/postgres-backup-credentials.yaml" <<EOF
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: postgres-backup-credentials
      namespace: $app_name
    spec:
      refreshInterval: "1h"
      secretStoreRef:
        name: openbao
        kind: ClusterSecretStore
      target:
        name: postgres-backup-credentials
        creationPolicy: Owner
        template:
          engineVersion: v2
          mergePolicy: Merge
          data:
            REGION: "eu-west-1"
      data:
        - secretKey: ACCESS_KEY_ID
          remoteRef:
            key: services/postgres
            property: PG_BACKUPS_ACCESS_KEY
        - secretKey: ACCESS_SECRET_KEY
          remoteRef:
            key: services/postgres
            property: PG_BACKUPS_SECRET_ACCESS_KEY
        - secretKey: ca.crt
          remoteRef:
            key: certificates/cert-manager-ca
            property: tls.crt
    EOF
        cat >> "$dir/base/kustomization.yaml" <<EOF
      - ./resources/postgres-backup-credentials.yaml
      - ./resources/cluster.yaml
      - ./resources/scheduled-backup.yaml
    EOF
    fi
    echo "Created $dir with overlay for cluster '$cluster_name'."
    if [ "$include_external_secret" = "true" ]; then
        echo "Included an application ExternalSecret; update its remote property names as needed."
    fi
    if [ "$include_postgres" = "true" ]; then
        echo "Included a CNPG cluster, scheduled backup, and backup credentials ExternalSecret."
    fi

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
