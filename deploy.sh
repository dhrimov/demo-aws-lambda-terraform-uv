#!/usr/bin/env bash
#
# Package the lambda (uv -> flat zip) and run terraform, in one step.
#
#   ./deploy.sh plan    package the lambda and show the terraform plan
#   ./deploy.sh apply   package the lambda and apply (prompts before changes)
#
# The lambda is always built fresh for arm64. Intermediate artifacts
# (build/, requirements.txt) are removed on exit; terraform/lambda.zip is
# left in place because terraform reads it on every plan and apply.

set -euo pipefail

# --- configuration ----------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

BUILD_DIR="$REPO_ROOT/build"
REQUIREMENTS="$REPO_ROOT/requirements.txt"
ROOT_ZIP="$REPO_ROOT/lambda.zip"
TF_DIR="$REPO_ROOT/terraform"
TF_ZIP="$TF_DIR/lambda.zip"

PLATFORM="aarch64-manylinux2014"
PYTHON_VERSION="3.13"

# --- helpers ----------------------------------------------------------------

log() {
  printf '\n==> %s\n' "$*"
}

usage() {
  cat <<EOF
Usage: ${0##*/} <plan|apply>

  plan   package the lambda and show the terraform plan
  apply  package the lambda and apply (prompts before changes)
EOF
}

# Remove the throwaway build artifacts. terraform/lambda.zip is intentionally
# kept: terraform needs it for filename and source_code_hash.
clean_intermediates() {
  rm -rf "$BUILD_DIR"
  rm -f "$REQUIREMENTS" "$ROOT_ZIP"
}

package() {
  clean_intermediates

  uv export --frozen --no-dev --no-editable -o "$REQUIREMENTS"

  uv pip install \
    --no-installer-metadata \
    --no-compile-bytecode \
    --python-platform "$PLATFORM" \
    --python "$PYTHON_VERSION" \
    --target "$BUILD_DIR" \
    -r "$REQUIREMENTS"

  # Dependencies first (flat at the zip root), then the application code.
  ( cd "$BUILD_DIR" && zip -qr "$ROOT_ZIP" . )
  ( cd "$REPO_ROOT" && zip -qr "$ROOT_ZIP" app )

  mv "$ROOT_ZIP" "$TF_ZIP"
}

# --- main -------------------------------------------------------------------

MODE="${1:-}"
case "$MODE" in
  plan | apply) ;;
  *)
    usage >&2
    exit 1
    ;;
esac

for tool in uv terraform zip; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "error: required tool not found on PATH: $tool" >&2
    exit 1
  }
done

# From here on we create artifacts, so tidy them up whatever happens.
trap clean_intermediates EXIT

log "[1/3] packaging (arm64)"
package

log "[2/3] terraform init"
( cd "$TF_DIR" && terraform init -input=false )

log "[3/3] terraform $MODE"
( cd "$TF_DIR" && terraform "$MODE" )