from __future__ import annotations

from uploadkit import InvalidExtension, UploadPolicy, Uploader
from uploadkit_testing import (
    FakeStorageProvider,
    MemoryUploadFile,
    assert_raises_uploader_error,
    assert_upload_fails,
    make_upload_file,
)


def test_fake_storage_records_put() -> None:
    storage = FakeStorageProvider(etag="e1")
    uploader = Uploader(UploadPolicy(), storage)
    result = uploader.upload(
        make_upload_file(b"hi", name="a.txt", content_type="text/plain"),
        bucket="b",
        object_name="a.txt",
    )
    assert result.etag == "e1"
    assert len(storage.objects) == 1
    assert storage.objects[0].body == b"hi"


def test_fake_storage_clear() -> None:
    storage = FakeStorageProvider()
    storage.put(bucket="b", object_name="o", body=b"x", content_type="text/plain")
    assert len(storage.objects) == 1
    storage.clear()
    assert storage.objects == []


def test_memory_upload_file_seek_tell() -> None:
    file = MemoryUploadFile(b"abcdef", name="a.bin")
    assert file.read(2) == b"ab"
    assert file.tell() == 2
    assert file.seek(0) == 0
    assert file.read() == b"abcdef"


def test_fake_storage_can_fail() -> None:
    from uploadkit import UploadFailed

    storage = FakeStorageProvider(fail=True)
    uploader = Uploader(UploadPolicy(), storage)
    assert_upload_fails(
        lambda: uploader.upload(make_upload_file(), bucket="b", object_name="x"),
        UploadFailed,
    )


def test_assert_raises_helper() -> None:
    class Boom:
        def validate(self, file, policy) -> None:  # noqa: ANN001
            raise InvalidExtension("bad ext")

    uploader = Uploader(UploadPolicy(validators=(Boom(),)), FakeStorageProvider())
    with assert_raises_uploader_error(InvalidExtension, match="bad ext"):
        uploader.upload(make_upload_file(), bucket="b", object_name="x")
