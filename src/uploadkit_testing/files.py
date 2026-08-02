"""In-memory uploadable file fixture."""

from __future__ import annotations

from io import BytesIO


class MemoryUploadFile:
    """Simple ``UploadableFile`` implementation for tests."""

    def __init__(
        self,
        content: bytes,
        *,
        name: str = "file.bin",
        content_type: str | None = "application/octet-stream",
    ) -> None:
        self._buffer = BytesIO(content)
        self.name = name
        self.size = len(content)
        self.content_type = content_type

    def read(self, size: int = -1) -> bytes:
        return self._buffer.read(size)

    def seek(self, offset: int, whence: int = 0) -> int:
        return self._buffer.seek(offset, whence)

    def tell(self) -> int:
        return self._buffer.tell()


def make_upload_file(
    content: bytes = b"test",
    *,
    name: str = "file.bin",
    content_type: str | None = "application/octet-stream",
) -> MemoryUploadFile:
    """Factory for an in-memory uploadable file."""
    return MemoryUploadFile(content, name=name, content_type=content_type)
