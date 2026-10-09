#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  cat >&2 <<'USAGE'
Usage: vendor-helm-chart.sh REPOSITORY CHART VERSION DESTINATION

REPOSITORY is a Helm repository URL, or an OCI registry URL such as
oci://ghcr.io/example/charts. VERSION may be an exact version or Helm
semver constraint. DESTINATION is the chart directory to replace.
USAGE
  exit 2
fi

repository=${1%/}
chart=$2
version=$3
destination=$4
helm=${HELM:-helm}

if ! command -v "$helm" >/dev/null 2>&1; then
  echo "Error: Helm executable '$helm' was not found." >&2
  exit 1
fi

if [[ -z "$repository" || -z "$chart" || -z "$version" || -z "$destination" ]]; then
  echo "Error: repository, chart, version, and destination must be non-empty." >&2
  exit 2
fi

repo_root=$(git rev-parse --show-toplevel)
if [[ "$destination" = /* ]]; then
  destination_path=$destination
else
  destination_path="$repo_root/$destination"
fi
parent_path=$(dirname "$destination_path")
mkdir -p "$parent_path"

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/vendor-helm-chart.XXXXXX")
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

if [[ "$repository" == oci://* ]]; then
  "$helm" pull "$repository/$chart" \
    --version "$version" \
    --untar \
    --untardir "$tmpdir"
else
  "$helm" pull --repo "$repository" "$chart" \
    --version "$version" \
    --untar \
    --untardir "$tmpdir"
fi

downloaded="$tmpdir/$chart"
if [[ ! -f "$downloaded/Chart.yaml" ]]; then
  echo "Error: Helm did not unpack '$chart' into '$tmpdir'." >&2
  exit 1
fi

chart_name=$(awk -F ': *' '/^name:/ { print $2; exit }' "$downloaded/Chart.yaml")
chart_version=$(awk -F ': *' '/^version:/ { print $2; exit }' "$downloaded/Chart.yaml")
if [[ "$chart_name" != "$chart" ]]; then
  echo "Error: requested chart '$chart', but package contains '$chart_name'." >&2
  exit 1
fi

if [[ -z "$chart_version" ]]; then
  echo "Error: chart '$chart' has no version in Chart.yaml." >&2
  exit 1
fi

temporary_chart="$tmpdir/chart"
mkdir -p "$temporary_chart"
{
  printf '# Vendored from %s\n' "$repository"
  cat "$downloaded/Chart.yaml"
} > "$temporary_chart/Chart.yaml"
mv "$temporary_chart/Chart.yaml" "$downloaded/Chart.yaml"

backup="$tmpdir/previous-chart"
if [[ -e "$destination_path" ]]; then
  mv "$destination_path" "$backup"
fi

if mv "$downloaded" "$destination_path"; then
  rm -rf "$backup"
else
  if [[ -e "$backup" ]]; then
    mv "$backup" "$destination_path"
  fi
  exit 1
fi

printf 'Vendored %s %s from %s into %s\n' "$chart_name" "$chart_version" "$repository" "${destination_path#"$repo_root"/}"
