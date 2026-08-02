"""Testing utilities for UploadKit.

Must never be used as runtime functionality in production.
"""

from uploadkit_testing.assertions import (
    assert_raises_uploader_error,
    assert_upload_fails,
)
from uploadkit_testing.files import MemoryUploadFile, make_upload_file
from uploadkit_testing.providers import FakeStorageProvider, StoredObject

__all__ = [
    "FakeStorageProvider",
    "StoredObject",
    "MemoryUploadFile",
    "make_upload_file",
    "assert_raises_uploader_error",
    "assert_upload_fails",
]

__version__ = "0.1.0"
