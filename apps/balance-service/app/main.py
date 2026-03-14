import grpc
import logging
from concurrent import futures

from generated import balance_pb2_grpc
from app.server import BalanceServicer

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

GRPC_PORT = "50051"
MAX_WORKERS = 10


def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=MAX_WORKERS))
    balance_pb2_grpc.add_BalanceServiceServicer_to_server(BalanceServicer(), server)

    server.add_insecure_port(f"[::]:{GRPC_PORT}")
    server.start()

    logger.info(f"balance-service listening on port {GRPC_PORT}")

    server.wait_for_termination()


if __name__ == "__main__":
    serve()