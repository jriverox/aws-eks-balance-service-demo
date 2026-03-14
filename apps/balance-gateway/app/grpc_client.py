import os
import grpc
import balance_pb2
import balance_pb2_grpc

# Address of balance-service resolved via Kubernetes internal DNS
BALANCE_SERVICE_ADDRESS = os.getenv("BALANCE_SERVICE_ADDRESS", "localhost:50051")


def get_balance(account_id: str) -> dict | None:
    """
    Opens a gRPC channel to balance-service, calls GetBalance,
    and returns the response as a plain dict.
    Raises grpc.RpcError on communication or application errors.
    """
    with grpc.insecure_channel(BALANCE_SERVICE_ADDRESS) as channel:
        stub = balance_pb2_grpc.BalanceServiceStub(channel)
        request = balance_pb2.BalanceRequest(account_id=account_id)
        response = stub.GetBalance(request)

    return {
        "account_id": response.account_id,
        "owner_name": response.owner_name,
        "balance": response.balance,
        "currency": response.currency,
        "last_updated": response.last_updated,
    }