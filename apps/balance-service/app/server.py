import grpc
import balance_pb2
import balance_pb2_grpc
from app.data import get_account


class BalanceServicer(balance_pb2_grpc.BalanceServiceServicer):
    """Implements the BalanceService gRPC contract defined in proto/balance.proto"""

    def GetBalance(self, request, context):
        account = get_account(request.account_id)

        if account is None:
            context.set_code(grpc.StatusCode.NOT_FOUND)
            context.set_details(f"Account '{request.account_id}' not found.")
            return balance_pb2.BalanceResponse()

        return balance_pb2.BalanceResponse(
            account_id=account["account_id"],
            owner_name=account["owner_name"],
            balance=account["balance"],
            currency=account["currency"],
            last_updated=account["last_updated"],
        )