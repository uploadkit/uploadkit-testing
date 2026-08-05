"""FastAPI upload demo for UploadKit performance testing."""

from __future__ import annotations

import os
import uuid

from fastapi import FastAPI, UploadFile
from uploadkit import AsyncUploader, UploadPolicy, Uploader, UploaderError
from uploadkit_fastapi import (
    as_async_source,
    as_uploadable,
    json_error_response,
    run_sync_upload,
)
from uploadkit_security import (
    AsyncChecksumValidator,
    ChecksumValidator,
    default_async_validators,
    default_validators,
)

from app.storage import AsyncS3Storage, Boto3S3Storage

MINIO_ENDPOINT = os.environ.get("MINIO_ENDPOINT", "http://minio:9000")
ACCESS_KEY = os.environ.get("MINIO_ROOT_USER", "minioadmin")
SECRET_KEY = os.environ.get("MINIO_ROOT_PASSWORD", "minioadmin")
BUCKET = os.environ.get("UPLOAD_BUCKET", "uploads")
MAX_SIZE = int(os.environ.get("UPLOAD_MAX_SIZE", str(110 * 1024 * 1024)))
ASYNC_CHUNK_SIZE = int(os.environ.get("ASYNC_CHUNK_SIZE", str(8 * 1024 * 1024)))
S3_PART_SIZE = int(os.environ.get("S3_PART_SIZE", str(5 * 1024 * 1024)))
ENABLE_CHECKSUM = os.environ.get("ENABLE_CHECKSUM", "1").lower() not in {
    "0",
    "false",
    "no",
    "off",
}
UVICORN_WORKERS = int(os.environ.get("UVICORN_WORKERS", "1"))

ALLOWED_EXTENSIONS = frozenset({"pdf", "png"})
ALLOWED_MIME_TYPES = frozenset({"application/pdf", "image/png"})

app = FastAPI(title="uploadkit-fastapi perf")

async_storage = AsyncS3Storage(
    endpoint_url=MINIO_ENDPOINT,
    access_key=ACCESS_KEY,
    secret_key=SECRET_KEY,
    part_size=S3_PART_SIZE,
)
boto3_storage = Boto3S3Storage(
    endpoint_url=MINIO_ENDPOINT,
    access_key=ACCESS_KEY,
    secret_key=SECRET_KEY,
)


def _object_name(filename: str | None) -> str:
    base = filename or "object"
    return f"perf/{uuid.uuid4().hex}-{base}"


def _async_policy() -> UploadPolicy:
    exclude = () if ENABLE_CHECKSUM else AsyncChecksumValidator
    return UploadPolicy(
        max_size=MAX_SIZE,
        allowed_extensions=ALLOWED_EXTENSIONS,
        allowed_mime_types=ALLOWED_MIME_TYPES,
        async_validators=default_async_validators(exclude=exclude),
    )


def _sync_policy() -> UploadPolicy:
    exclude = () if ENABLE_CHECKSUM else ChecksumValidator
    return UploadPolicy(
        max_size=MAX_SIZE,
        allowed_extensions=ALLOWED_EXTENSIONS,
        allowed_mime_types=ALLOWED_MIME_TYPES,
        validators=default_validators(exclude=exclude),
    )


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "async_chunk_size": ASYNC_CHUNK_SIZE,
        "s3_part_size": S3_PART_SIZE,
        "enable_checksum": ENABLE_CHECKSUM,
        "uvicorn_workers": UVICORN_WORKERS,
    }


@app.post("/upload")
async def upload(file: UploadFile):
    try:
        result = await AsyncUploader(
            _async_policy(),
            async_storage,
            chunk_size=ASYNC_CHUNK_SIZE,
        ).upload(
            as_async_source(file),
            bucket=BUCKET,
            object_name=_object_name(file.filename),
        )
    except UploaderError as exc:
        return json_error_response(exc)
    return {
        "object_name": result.object_name,
        "sha256": result.sha256,
        "etag": result.etag,
        "mode": "async",
    }


@app.post("/upload-sync")
async def upload_sync(file: UploadFile):
    try:
        result = await run_sync_upload(
            Uploader(_sync_policy(), boto3_storage),
            as_uploadable(file),
            bucket=BUCKET,
            object_name=_object_name(file.filename),
        )
    except UploaderError as exc:
        return json_error_response(exc)
    return {
        "object_name": result.object_name,
        "sha256": result.sha256,
        "etag": result.etag,
        "mode": "sync",
    }
