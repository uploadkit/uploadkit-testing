"""Assertion helpers for UploadKit tests."""

from __future__ import annotations

from collections.abc import Callable
from contextlib import AbstractContextManager
from typing import TypeVar

import pytest

from uploadkit import UploaderError

E = TypeVar("E", bound=UploaderError)


def assert_raises_uploader_error(
    exc_type: type[E],
    match: str | None = None,
) -> AbstractContextManager[pytest.ExceptionInfo[E]]:
    """Expect an ``UploaderError`` subclass to be raised."""
    return pytest.raises(exc_type, match=match)


def assert_upload_fails(
    call: Callable[[], object],
    exc_type: type[UploaderError],
    *,
    match: str | None = None,
) -> None:
    """Invoke ``call`` and assert it raises ``exc_type``."""
    with pytest.raises(exc_type, match=match):
        call()
