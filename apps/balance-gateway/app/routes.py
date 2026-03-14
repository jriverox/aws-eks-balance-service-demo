import grpc
import logging
from fastapi import APIRouter, HTTPException
from app.grpc_client import get_balance

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/balance/{account_id}")
async def balance(account_id: str):
    """
    Retrieves the balance for a given account_id.
    Translates gRPC errors into appropriate HTTP status codes.
    """
    try:
        result = get_balance(account_id)
        return result

    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail=f"Account '{account_id}' not found.")
        logger.error(f"gRPC error: {e.code()} — {e.details()}")
        raise HTTPException(status_code=502, detail="Error communicating with balance-service.")