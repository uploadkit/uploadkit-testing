# FastAPI upload performance harness

Docker Compose stack to measure UploadKit FastAPI upload performance against MinIO using **curl** (smoke) and **k6** (load).

Requires the monorepo sibling layout:

```
uploadkit/
  uploadkit/
  uploadkit-fastapi/
  uploadkit-security/
  uploadkit-testing/   # this package; run compose from perf/
```

## Chunk / worker guidance

See **[CHUNK_SIZE_GUIDE.md](CHUNK_SIZE_GUIDE.md)** for how to choose `AsyncUploader.chunk_size`, S3 multipart `part_size`, and uvicorn workers from average file size and concurrency (with numbers from the k6 runs in this harness).

## Payloads

Generated at runtime into `artifacts/payloads/` (not committed):

| File | Size | Notes |
|------|------|--------|
| `fake-100mb.pdf` | 100 MB | `%PDF-1.4` magic + padding |
| `fake-10mb.png` | 10 MB | PNG signature + padding |

## Services

| Service | Port | Role |
|---------|------|------|
| `minio` | 9000 / 9001 | Object storage + console |
| `minio_init` | — | Creates `uploads` bucket |
| `api` | 8000 | FastAPI demo (`/upload`, `/upload-sync`, `/health`) |
| `bench` | — | k6 runner (Compose profile `bench`) |

## Quick start

```bash
cd uploadkit-testing/perf

# Start MinIO + API
docker compose up --build -d minio minio_init api

# Smoke (single curl uploads)
API_BASE=http://127.0.0.1:8000 ARTIFACTS_DIR=./artifacts ./scripts/smoke_curl.sh

# Load with host k6 (recommended if Docker Hub pulls are flaky)
API_BASE=http://127.0.0.1:8000 ARTIFACTS_DIR=./artifacts ./scripts/load_k6.sh

# Or via compose profile
docker compose --profile bench run --rm bench ./scripts/load_k6.sh
```

Reports land in `./artifacts/` (`k6-*.txt`, `k6-*.json`).

### Env knobs

| Variable | Default | Meaning |
|----------|---------|---------|
| `PAYLOAD` | `both` | `pdf` \| `png` \| `both` |
| `UPLOAD_ENDPOINT` | `both` | `async` \| `sync` \| `both` |
| `K6_VUS_PNG` / `K6_ITER_PNG` | `4` / `20` | VUs / iterations for 10 MB PNG |
| `K6_VUS_PDF` / `K6_ITER_PDF` | `2` / `5` | VUs / iterations for 100 MB PDF |

Example — PNG only, async only:

```bash
PAYLOAD=png UPLOAD_ENDPOINT=async K6_VUS_PNG=8 K6_ITER_PNG=40 \
  API_BASE=http://127.0.0.1:8000 ARTIFACTS_DIR=./artifacts ./scripts/load_k6.sh
```

## Endpoints under test

- `POST /upload` — async streaming (`AsyncUploader` + aioboto3)
- `POST /upload-sync` — sync stack in a worker thread (`run_sync_upload` + boto3)
