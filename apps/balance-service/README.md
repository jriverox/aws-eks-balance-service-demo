# balance-service

gRPC server that handles balance queries and returns structured financial data from in-memory store.

## Responsibilities

- Implement the BalanceService gRPC contract defined in proto/balance.proto
- Serve balance data for account queries
- Expose gRPC port internally within the EKS cluster (ClusterIP)
