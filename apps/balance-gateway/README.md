# balance-gateway

FastAPI REST gateway that translates HTTP requests to gRPC calls toward balance-service.

## Responsibilities

- Expose REST endpoints for external consumers via ALB
- Translate HTTP → gRPC protocol internally
- Return structured JSON responses
