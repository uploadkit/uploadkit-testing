"""Fake storage provider for tests."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class StoredObject:
    bucket: str
    object_name: str
    body: bytes
    content_type: str


@dataclass
class FakeStorageProvider:
    """Records puts and returns a configurable etag.

    Not for production use.
    """

    etag: str | None = "fake-etag"
    fail: bool = False
    objects: list[StoredObject] = field(default_factory=list)

    def put(
        self,
        *,
        bucket: str,
        object_name: str,
        body: bytes,
        content_type: str,
    ) -> str | None:
        if self.fail:
            raise RuntimeError("FakeStorageProvider configured to fail")
        self.objects.append(
            StoredObject(
                bucket=bucket,
                object_name=object_name,
                body=body,
                content_type=content_type,
            )
        )
        return self.etag

    def clear(self) -> None:
        self.objects.clear()
