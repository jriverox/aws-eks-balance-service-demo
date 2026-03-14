# =============================================================================
# Stage 1 — Builder
# Installs dependencies, generates gRPC stubs
# =============================================================================
FROM python:3.11-slim AS builder

WORKDIR /app

# Install system dependencies required by grpcio
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Install Poetry
RUN pip install poetry==1.8.2 --no-cache-dir

# Copy Poetry files
# COPY pyproject.toml poetry.lock* ./
COPY apps/balance-service/pyproject.toml apps/balance-service/poetry.lock* ./

# Install all dependencies including dev (needed for grpcio-tools)
RUN poetry config virtualenvs.in-project true && \
    poetry install --no-interaction --no-ansi

# Copy proto file and generate stubs
# COPY ../../proto /proto
COPY proto/ /proto
RUN poetry run python -m grpc_tools.protoc \
    --proto_path=/proto \
    --python_out=/proto/generated \
    --grpc_python_out=/proto/generated \
    /proto/balance.proto

# Copy application source
# COPY app/ ./app/
COPY apps/balance-service/app/ ./app/

# =============================================================================
# Stage 2 — Runtime
# Lean image with only production artifacts
# =============================================================================
FROM python:3.11-slim AS runtime

WORKDIR /app

# Copy virtualenv from builder (production deps only)
COPY --from=builder /app/.venv /app/.venv

# Copy application source
COPY --from=builder /app/app ./app

# Copy generated proto stubs
COPY --from=builder /proto/generated /proto/generated

# Set PYTHONPATH so app can find generated stubs
ENV PYTHONPATH=/proto:/proto/generated
ENV PATH="/app/.venv/bin:$PATH"

EXPOSE 50051

CMD ["python", "-m", "app.main"]
