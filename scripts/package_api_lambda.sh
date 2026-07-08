#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_DIR="${ROOT_DIR}"
BUILD_DIR="${ROOT_DIR}/dist/lambda-api"
ZIP_PATH="${ROOT_DIR}/dist/stockbrief-api-lambda.zip"
LAMBDA_PYTHON_PLATFORM="${LAMBDA_PYTHON_PLATFORM:-x86_64-manylinux2014}"
LAMBDA_PYTHON_VERSION="${LAMBDA_PYTHON_VERSION:-3.13}"

rm -rf "${BUILD_DIR}" "${ZIP_PATH}"
mkdir -p "${BUILD_DIR}" "${ROOT_DIR}/dist"
REQUIREMENTS_FILE="$(mktemp)"
trap 'rm -f "${REQUIREMENTS_FILE}"' EXIT

uv export \
  --quiet \
  --project "${API_DIR}" \
  --format requirements.txt \
  --locked \
  --no-dev \
  --no-emit-project \
  --prune greenlet \
  --prune uvicorn \
  --output-file "${REQUIREMENTS_FILE}"

uv pip install \
  --target "${BUILD_DIR}" \
  --python-platform "${LAMBDA_PYTHON_PLATFORM}" \
  --python-version "${LAMBDA_PYTHON_VERSION}" \
  --no-deps \
  --only-binary=:all: \
  --requirement "${REQUIREMENTS_FILE}"

cp -R "${API_DIR}/app" "${BUILD_DIR}/app"
cp -R "${API_DIR}/migrations" "${BUILD_DIR}/migrations"
cp "${API_DIR}/alembic.ini" "${BUILD_DIR}/alembic.ini"

find "${BUILD_DIR}" -type d -name "__pycache__" -prune -exec rm -rf {} +
find "${BUILD_DIR}" -exec touch -t 198001010000 {} +

(
  cd "${BUILD_DIR}"
  if command -v python3 &>/dev/null; then
    PYTHON_CMD="python3"
  elif command -v python &>/dev/null; then
    PYTHON_CMD="python"
  elif command -v py &>/dev/null; then
    PYTHON_CMD="py"
  else
    echo "Error: Python is required to create the zip archive but was not found."
    exit 1
  fi

  $PYTHON_CMD -c "
import zipfile, os, sys
with zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk('.'):
        for file in sorted(files):
            file_path = os.path.join(root, file)
            arcname = os.path.relpath(file_path, '.').replace(os.sep, '/')
            zf.write(file_path, arcname)
" "${ZIP_PATH}"
)

echo "Packaged ${ZIP_PATH}"
