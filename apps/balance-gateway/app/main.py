import logging
import uvicorn
from fastapi import FastAPI
from app.routes import router

logging.basicConfig(level=logging.INFO)

app = FastAPI(
    title="balance-gateway",
    description="REST gateway that translates HTTP requests to gRPC calls toward balance-service",
    version="0.1.0",
)

app.include_router(router)


@app.get("/health")
async def health():
    return {"status": "ok"}


if __name__ == "__main__":
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=False)