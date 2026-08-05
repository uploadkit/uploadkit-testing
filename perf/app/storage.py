"""S3-compatible storage for AWS S3 or MinIO (perf demo only)."""

from __future__ import annotations

import os

import aioboto3
import boto3
from botocore.client import Config

DEFAULT_PART_SIZE = 5 * 1024 * 1024  # 5 MiB (S3 minimum except last part)


def _client_config() -> Config:
    return Config(signature_version="s3v4", s3={"addressing_style": "path"})


class Boto3S3Storage:
    """S3-compatible sync storage for AWS S3 or MinIO."""

    def __init__(
        self,
        *,
        access_key: str,
        secret_key: str,
        region: str = "us-east-1",
        endpoint_url: str | None = None,
    ) -> None:
        kwargs: dict = {
            "service_name": "s3",
            "aws_access_key_id": access_key,
            "aws_secret_access_key": secret_key,
            "region_name": region,
            "config": _client_config(),
        }
        if endpoint_url:
            kwargs["endpoint_url"] = endpoint_url
        self.client = boto3.client(**kwargs)

    def put(self, *, bucket, object_name, body, content_type):
        resp = self.client.put_object(
            Bucket=bucket,
            Key=object_name,
            Body=body,
            ContentType=content_type,
        )
        return resp.get("ETag")


class AsyncS3Writer:
    def __init__(
        self,
        client,
        *,
        bucket: str,
        object_name: str,
        content_type: str,
        part_size: int,
    ) -> None:
        if part_size <= 0:
            raise ValueError("part_size must be positive")
        self._client = client
        self._bucket = bucket
        self._key = object_name
        self._content_type = content_type
        self._part_size = part_size
        self._upload_id: str | None = None
        self._parts: list[dict] = []
        self._buffer = bytearray()
        self._part_number = 1

    async def _ensure_upload(self) -> None:
        if self._upload_id is not None:
            return
        resp = await self._client.create_multipart_upload(
            Bucket=self._bucket,
            Key=self._key,
            ContentType=self._content_type,
        )
        self._upload_id = resp["UploadId"]

    async def _flush_part(self, data: bytes) -> None:
        await self._ensure_upload()
        assert self._upload_id is not None
        resp = await self._client.upload_part(
            Bucket=self._bucket,
            Key=self._key,
            PartNumber=self._part_number,
            UploadId=self._upload_id,
            Body=data,
        )
        self._parts.append({"ETag": resp["ETag"], "PartNumber": self._part_number})
        self._part_number += 1

    async def write(self, chunk: bytes) -> None:
        self._buffer.extend(chunk)
        while len(self._buffer) >= self._part_size:
            part = bytes(self._buffer[: self._part_size])
            del self._buffer[: self._part_size]
            await self._flush_part(part)

    async def abort(self) -> None:
        if self._upload_id is None:
            return
        await self._client.abort_multipart_upload(
            Bucket=self._bucket,
            Key=self._key,
            UploadId=self._upload_id,
        )
        self._upload_id = None

    async def complete(self) -> str | None:
        if self._buffer:
            await self._flush_part(bytes(self._buffer))
            self._buffer.clear()
        if self._upload_id is None:
            resp = await self._client.put_object(
                Bucket=self._bucket,
                Key=self._key,
                Body=b"",
                ContentType=self._content_type,
            )
            return resp.get("ETag")
        resp = await self._client.complete_multipart_upload(
            Bucket=self._bucket,
            Key=self._key,
            UploadId=self._upload_id,
            MultipartUpload={"Parts": self._parts},
        )
        self._upload_id = None
        return resp.get("ETag")


class AsyncS3Storage:
    """S3-compatible async storage for AWS S3 or MinIO."""

    def __init__(
        self,
        *,
        access_key: str,
        secret_key: str,
        region: str = "us-east-1",
        endpoint_url: str | None = None,
        part_size: int | None = None,
    ) -> None:
        self._session = aioboto3.Session()
        self._client_kwargs: dict = {
            "service_name": "s3",
            "aws_access_key_id": access_key,
            "aws_secret_access_key": secret_key,
            "region_name": region,
            "config": _client_config(),
        }
        if endpoint_url:
            self._client_kwargs["endpoint_url"] = endpoint_url
        if part_size is None:
            part_size = int(os.environ.get("S3_PART_SIZE", str(DEFAULT_PART_SIZE)))
        self._part_size = part_size
        self._cm = None
        self._client = None

    async def _get_client(self):
        if self._client is None:
            self._cm = self._session.client(**self._client_kwargs)
            self._client = await self._cm.__aenter__()
        return self._client

    async def open_write(self, *, bucket: str, object_name: str, content_type: str):
        client = await self._get_client()
        return AsyncS3Writer(
            client,
            bucket=bucket,
            object_name=object_name,
            content_type=content_type,
            part_size=self._part_size,
        )
