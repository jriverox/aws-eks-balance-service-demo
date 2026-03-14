#!/usr/bin/env bash
# =============================================================================
# generate_proto.sh
# Generates Python gRPC stubs from proto/balance.proto
# Output: proto/generated/
# Usage: ./scripts/generate_proto.sh
# =============================================================================

# **`set -euo pipefail`** — El script se detiene inmediatamente si cualquier comando falla, 
# si hay variables no definidas, o si falla algún comando en un pipe.
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROTO_DIR="${REPO_ROOT}/proto"
OUTPUT_DIR="${PROTO_DIR}/generated"

log_info()    { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# -----------------------------------------------------------------------------
# Validate grpcio-tools is available
# -----------------------------------------------------------------------------
log_info "Checking for grpcio-tools..."

if ! python -c "import grpc_tools" &>/dev/null; then
  log_error "grpcio-tools is not installed."
  log_error "Run: pip install grpcio-tools  or  poetry install (from either app directory)"
  exit 1
fi

log_info "grpcio-tools found."

# -----------------------------------------------------------------------------
# Validate proto file exists
# -----------------------------------------------------------------------------
PROTO_FILE="${PROTO_DIR}/balance.proto"

if [ ! -f "${PROTO_FILE}" ]; then
  log_error "Proto file not found: ${PROTO_FILE}"
  exit 1
fi

# -----------------------------------------------------------------------------
# Create output directory
# -----------------------------------------------------------------------------
mkdir -p "${OUTPUT_DIR}"

# Create __init__.py so generated/ is a proper Python package
touch "${OUTPUT_DIR}/__init__.py"

# -----------------------------------------------------------------------------
# Generate stubs
# -----------------------------------------------------------------------------
log_info "Generating Python stubs from balance.proto..."

# **`python -m grpc_tools.protoc`** — En lugar de llamar al binario `protoc` directamente, 
# usamos el módulo Python de `grpcio-tools`. 
# Esto garantiza usar exactamente la versión instalada en el entorno Poetry, sin depender de una instalación global de `protoc`.

python -m grpc_tools.protoc \
  --proto_path="${PROTO_DIR}" \
  --python_out="${OUTPUT_DIR}" \
  --grpc_python_out="${OUTPUT_DIR}" \
  "${PROTO_FILE}"

if [ $? -ne 0 ]; then
  log_error "protoc failed. Check the proto file for syntax errors."
  exit 1
fi

log_info "Stubs generated successfully in ${OUTPUT_DIR}"
log_info "Files:"
ls "${OUTPUT_DIR}"

# -----------------------------------------------------------------------------
# Reminder: PYTHONPATH must include proto/ for both apps to find generated/
# -----------------------------------------------------------------------------
echo ""
log_warn "Remember to set PYTHONPATH before running the apps locally:"
log_warn "  export PYTHONPATH=${REPO_ROOT}/proto:\$PYTHONPATH"
echo ""
log_info "Done."