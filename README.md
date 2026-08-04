# uploadkit-testing

Testing utilities for UploadKit.

## What problem does this solve?

Provides fake storage providers, in-memory upload files, and assertion helpers so packages and apps can test upload pipelines without real object storage.

## When to use it

Use this package in tests only.

## When not to use it

Never ship this as runtime functionality in production.

## Installation

Requires **Python 3.10+**.

```bash
pip install uploadkit-testing
```

## Quick Start

```python
from uploadkit import Uploader, UploadPolicy
from uploadkit_testing import FakeStorageProvider, make_upload_file

storage = FakeStorageProvider()
uploader = Uploader(UploadPolicy(), storage)
result = uploader.upload(
    make_upload_file(b"hello", name="hello.txt"),
    bucket="test",
    object_name="hello.txt",
)
assert result.etag == "fake-etag"
```

## Architecture

Thin test doubles that satisfy UploadKit Core protocols. No production code paths.

## Public API

| Symbol | Kind |
|--------|------|
| `FakeStorageProvider` | Public |
| `MemoryUploadFile` / `make_upload_file` | Public |
| `assert_raises_uploader_error` / `assert_upload_fails` | Public |

## Performance

Docker Compose harness for FastAPI upload performance (MinIO + curl/hey) lives in [`perf/`](perf/). See [`perf/README.md`](perf/README.md).

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
