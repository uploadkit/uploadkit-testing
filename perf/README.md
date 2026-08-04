# FastAPI upload performance harness

Docker Compose stack to measure UploadKit FastAPI upload performance against MinIO using **curl** (smoke) and **hey** (load).

Requires the monorepo sibling layout:

```
uploadkit/
  uploadkit/
  uploadkit-fastapi/
  uploadkit-security/
  uploadkit-testing/   # this package; run compose from perf/
```

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
| `bench` | — | curl + hey (Compose profile `bench`) |

## Quick start

```bash
cd uploadkit-testing/perf

# Start MinIO + API
docker compose up --build -d minio minio_init api

# Smoke (single curl uploads, both payloads × both endpoints)
docker compose --profile bench run --rm bench ./scripts/smoke_curl.sh

# Load (hey concurrency)
docker compose --profile bench run --rm bench ./scripts/load_hey.sh
```

Reports land in `./artifacts/`.

### Env knobs

| Variable | Default | Meaning |
|----------|---------|---------|
| `PAYLOAD` | `both` | `pdf` \| `png` \| `both` |
| `UPLOAD_ENDPOINT` | `both` | `async` \| `sync` \| `both` |
| `HEY_N_PNG` / `HEY_C_PNG` | `50` / `5` | hey total / concurrency for 10 MB PNG |
| `HEY_N_PDF` / `HEY_C_PDF` | `10` / `2` | hey total / concurrency for 100 MB PDF |

Example — PNG only, async only, higher concurrency:

```bash
PAYLOAD=png UPLOAD_ENDPOINT=async HEY_N_PNG=100 HEY_C_PNG=10 \
  docker compose --profile bench run --rm bench ./scripts/load_hey.sh
```

## Endpoints under test

- `POST /upload` — async streaming (`AsyncUploader` + aioboto3)
- `POST /upload-sync` — sync stack in a worker thread (`run_sync_upload` + boto3)
