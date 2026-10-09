#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(git -C "$script_dir/.." rev-parse --show-toplevel)
cd "$repo_root"

helm=${HELM:-helm}
if ! command -v "$helm" >/dev/null 2>&1; then
  echo "Error: Helm executable '$helm' was not found." >&2
  exit 1
fi

read_chart_field() {
  local field=$1
  local manifest=$2

  awk -v key="$field" '
    $0 ~ ("^" key ":[[:space:]]*") {
      value = $0
      sub("^[^:]+:[[:space:]]*", "", value)
      sub(/[[:space:]]+#.*$/, "", value)
      gsub(/["\047]/, "", value)
      print value
      exit
    }
  ' "$manifest"
}

mapfile -d '' -t changed_files < <(
  git diff --name-only --diff-filter=ACMRT -z HEAD -- applications
)

refreshed=0
for manifest in "${changed_files[@]}"; do
  [[ "$manifest" =~ ^applications/[^/]+/charts/[^/]+/Chart\.yaml$ ]] || continue
  [[ -f "$manifest" ]] || continue

  IFS= read -r source_line < "$manifest" || true
  if [[ "$source_line" != '# Vendored from '* ]]; then
    echo "Error: '$manifest' has no '# Vendored from' source marker." >&2
    exit 1
  fi
  repository=${source_line#'# Vendored from '}

  case "$repository" in
    http://* | https://* | oci://*) ;;
    *)
      echo "Error: unsupported Helm repository '$repository' in '$manifest'." >&2
      exit 1
      ;;
  esac

  chart=$(read_chart_field name "$manifest")
  version=$(read_chart_field version "$manifest")
  if [[ ! "$chart" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "Error: invalid chart name '$chart' in '$manifest'." >&2
    exit 1
  fi
  if [[ ! "$version" =~ ^[A-Za-z0-9][A-Za-z0-9.+_-]*$ ]]; then
    echo "Error: invalid chart version '$version' in '$manifest'." >&2
    exit 1
  fi

  destination=${manifest%/Chart.yaml}
  bash scripts/vendor-helm-chart.sh "$repository" "$chart" "$version" "$destination"
  refreshed=$((refreshed + 1))
done

if [[ "$refreshed" -eq 0 ]]; then
  echo "No changed vendored Helm charts to refresh."
else
  echo "Refreshed $refreshed vendored Helm chart(s)."
fi
