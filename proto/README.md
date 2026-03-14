# proto/

This directory contains the shared gRPC contract (.proto files) for all services.

## Files

- `balance.proto` — Service definition for BalanceService (to be implemented)

## Code Generation

Generated Python stubs are excluded from version control (see .gitignore).
To regenerate after modifying the proto file:

```bash
./scripts/generate_proto.sh
```
