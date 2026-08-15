#!/usr/bin/env bash
#
# Package a Python project into an AWS Lambda deployment zip.
#
#   build.sh --input <dir> --output <dir> --python <version> --platform <platform>
#
# Builds the project as a wheel, installs it together with its locked
# dependencies into a throwaway venv targeting the Lambda platform, and hands
# that venv to package-python-function, which writes a reproducible zip named
# after the project.

set -euo pipefail

# --- configuration ----------------------------------------------------------

PACKAGER_VERSION="0.0.12"

# --- helpers ----------------------------------------------------------------

log() {
  printf '\n==> %s\n' "$*"
}

usage() {
  cat <<EOF
Usage: ${0##*/} --input <dir> --output <dir> --python <version> --platform <platform>
                [--build-dir <dir>]

  --input      directory containing the project's pyproject.toml
  --output     directory to write the zip into (created if missing)
  --python     Python version to build against, e.g. 3.13
  --platform   uv target platform, e.g. aarch64-manylinux2014
  --build-dir  scratch directory for intermediates, wiped before and after
               the build. Defaults to <input>/build

The first four are required: a default platform would silently decide the
architecture of every compiled dependency in the package.

Example:
  ${0##*/} --input . --output terraform --python 3.13 --platform aarch64-manylinux2014
EOF
}

die() {
  echo "error: $*" >&2
  usage >&2
  exit 1
}

# --- arguments --------------------------------------------------------------

INPUT=""
OUTPUT=""
PYTHON_VERSION=""
PLATFORM=""
BUILD_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --input | --output | --python | --platform | --build-dir)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      case "$1" in
        --input) INPUT="$2" ;;
        --output) OUTPUT="$2" ;;
        --python) PYTHON_VERSION="$2" ;;
        --platform) PLATFORM="$2" ;;
        --build-dir) BUILD_DIR="$2" ;;
      esac
      shift 2
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$INPUT" ]] || die "missing --input"
[[ -n "$OUTPUT" ]] || die "missing --output"
[[ -n "$PYTHON_VERSION" ]] || die "missing --python"
[[ -n "$PLATFORM" ]] || die "missing --platform"

for tool in uv uvx; do
  command -v "$tool" >/dev/null 2>&1 ||
    die "required tool not found on PATH: $tool"
done

[[ -f "$INPUT/pyproject.toml" ]] || die "no pyproject.toml in: $INPUT"

# Resolve every path now, so the uv --directory below cannot skew them.
INPUT="$(cd "$INPUT" && pwd)"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"

mkdir -p "${BUILD_DIR:=$INPUT/build}"
BUILD_DIR="$(cd "$BUILD_DIR" && pwd)"

# Everything below deletes this directory, so refuse the two paths that would
# take the project or the finished zip with it.
[[ "$BUILD_DIR" != "$INPUT" ]] || die "--build-dir must not be the input directory"
[[ "$BUILD_DIR" != "$OUTPUT" ]] || die "--build-dir must not be the output directory"

# --- main -------------------------------------------------------------------

# Every intermediate lives under the build directory, so cleanup has one
# predictable target and never reaches a path outside it.
clean_build_dir() {
  rm -rf "$BUILD_DIR"
}

trap clean_build_dir EXIT
clean_build_dir
mkdir -p "$BUILD_DIR"

log "[1/5] exporting locked dependencies"
uv export \
  --directory "$INPUT" \
  --frozen \
  --no-dev \
  --no-editable \
  --no-emit-project \
  -o "$BUILD_DIR/requirements.txt"

log "[2/5] building wheel"
uv build --directory "$INPUT" --wheel -o "$BUILD_DIR/dist"

log "[3/5] creating venv (python $PYTHON_VERSION)"
uv venv --python "$PYTHON_VERSION" "$BUILD_DIR/venv"

log "[4/5] installing wheel and dependencies for $PLATFORM"
uv pip install \
  --python "$BUILD_DIR/venv/bin/python" \
  --python-platform "$PLATFORM" \
  --only-binary=:all: \
  --no-installer-metadata \
  --no-compile-bytecode \
  "$BUILD_DIR"/dist/*.whl \
  -r "$BUILD_DIR/requirements.txt"

log "[5/5] packaging"
uvx "package-python-function@$PACKAGER_VERSION" \
  "$BUILD_DIR/venv" \
  --project "$INPUT/pyproject.toml" \
  --output-dir "$OUTPUT"
