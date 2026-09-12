import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from app.logging_config import configure_logging, get_logger
from app.models import Asset, HealthResponse, Insight
from app.services import calculate_insights, get_assets

configure_logging()
logger = get_logger(__name__)

ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "http://localhost:3000").split(",")


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("startup", version="1.0.0", allowed_origins=ALLOWED_ORIGINS)
    yield
    logger.info("shutdown")


app = FastAPI(
    title="Portfolio API",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs" if os.getenv("ENV") != "prod" else None,
    redoc_url="/redoc" if os.getenv("ENV") != "prod" else None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "OPTIONS"],
    allow_headers=["*"],
)


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(
        "unhandled_exception",
        method=request.method,
        path=request.url.path,
        error=str(exc),
        error_type=type(exc).__name__,
    )
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"},
    )


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        logger.info(
            "request",
            method=request.method,
            path=request.url.path,
            status_code=response.status_code,
        )
        return response


app.add_middleware(RequestLoggingMiddleware)


@app.get("/health", response_model=HealthResponse)
def health_check():
    return HealthResponse(status="healthy", version="1.0.0")


@app.get("/assets", response_model=list[Asset])
def list_assets():
    return get_assets()


@app.get("/insights", response_model=list[Insight])
def list_insights():
    assets = get_assets()
    return calculate_insights(assets)
