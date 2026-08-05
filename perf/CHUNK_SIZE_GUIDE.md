# Choosing chunk / part sizes and workers

Developer guide based on UploadKit’s async/sync pipelines and the k6 runs in this `perf/` harness (MinIO + FastAPI, local Docker).

Use this when wiring `AsyncUploader(chunk_size=…)`, S3 multipart `part_size`, and `uvicorn --workers`.

---

## What actually exists

| Knob | Applies to | Default in Core / this harness | Effect |
|------|------------|--------------------------------|--------|
| **`AsyncUploader.chunk_size`** | Async only | Core **1 MiB**; harness often **8 MiB** | Bytes read per loop → validators → storage writer |
| **S3 multipart `part_size`** | Async S3/MinIO writer | **5 MiB** (S3 minimum except last part) | How large each `upload_part` is |
| **Sync “chunk”** | — | **None** | Sync does **one full `file.read()`** then `put_object` |
| **Uvicorn workers** | Process concurrency | Harness A/B used **4** | Parallel uploads across processes |

Sync has **no chunk size**. For large or concurrent files, prefer async.

---

## Measured results (this harness)

Environment: Docker Desktop, MinIO + API on one machine, k6 on host.

### A. Async read `chunk_size` 1 MiB vs 8 MiB

Checksum **on**, **1** worker, async+sync mixed:

| Payload | 1 MiB avg | 8 MiB avg | Delta |
|---------|-----------|-----------|-------|
| 10 MB PNG (40 reqs) | 7.42 s | 7.44 s | ~0% |
| 100 MB PDF (10 reqs) | 35.74 s | 35.28 s | ~−1% |

**Conclusion:** Changing async read chunk between 1–8 MiB barely moves end-to-end latency here. Pick for **memory / simplicity**, not raw speed.

### B. S3 `part_size` 5 MiB vs 16 MiB

Checksum **off**, **4** workers, **async only**:

| Payload | 5 MiB avg | 16 MiB avg | Delta |
|---------|-----------|------------|-------|
| 10 MB PNG (20 reqs) | 3.90 s | 3.85 s | ~−1.5% |
| 100 MB PDF (5 reqs) | 17.41 s | 18.10 s | ~+4% |

**Conclusion:** 16 MiB parts did **not** clearly beat 5 MiB. Prefer **5 MiB** unless you re-benchmark on real AWS with higher concurrency.

### C. What *did* move the needle

Same payloads, comparing early “heavy” config vs tuned async-only:

| Change | Effect on wall time |
|--------|---------------------|
| Async vs sync for large files | Sync holds whole object in RAM; avoid under load |
| Drop SHA-256 checksum | Large CPU save on big bodies |
| 1 → 4 uvicorn workers | Better parallel throughput under concurrent VUs |
| `chunk_size` / `part_size` tweaks | Small / noise-level in these runs |

---

## Recommendation matrix

Let **F** = typical / average upload size, **W** = uvicorn (or Gunicorn) workers, **C** = expected concurrent uploads **per worker** (roughly k6 VUs / W under load).

Peak RAM ballpark:

- **Async:** ≈ `W × C × max(chunk_size, part_size)` (+ small overhead)  
- **Sync:** ≈ `W × C × F` (full file buffered)

### By average file size

| Average file size **F** | Path | Suggested `chunk_size` | Suggested S3 `part_size` | Notes |
|-------------------------|------|------------------------|---------------------------|--------|
| **&lt; 1 MB** | Sync OK | n/a | n/a (single `put`) | Keep it simple |
| **1–10 MB** | Prefer async | **1 MiB** | **5 MiB** | Part size ≥ file → often one part after buffer flush |
| **10–50 MB** | Async | **1–8 MiB** | **5–8 MiB** | 8 MiB chunk is fine; no proven latency win over 1 MiB |
| **50–200 MB** | Async only | **8 MiB** | **5–8 MiB** | Avoid sync; consider disabling checksum if product allows |
| **&gt; 200 MB** | Async only | **8 MiB** | **8–16 MiB** | Re-benchmark `part_size` on target cloud; parallel parts may matter more than size |

### By worker count

| Workers **W** | Concurrent uploads (total) | Guidance |
|---------------|----------------------------|----------|
| **1** | Low | `chunk_size=1 MiB`, `part_size=5 MiB` is enough |
| **2–4** | Medium (e.g. 4–16 VUs) | Keep `chunk_size` ≤ **8 MiB**, `part_size` **5 MiB**; watch RAM ≈ `W×C×8 MiB` |
| **8+** | High | Prefer **smaller** chunks (**1 MiB**) so `W×C×chunk` stays bounded; scale horizontally before enlarging buffers |

**Rule of thumb:**  
`W × C × chunk_size ≲ 10–20% of container memory`.  
Example: 4 workers × 4 concurrent × 8 MiB ≈ **128 MiB** buffers alone — fine on a 1–2 GiB service; raise carefully.

---

## Decision cheat sheet

```
if F < 1MB:
    use sync Uploader (or async; either fine)
elif need max throughput under concurrency:
    async + checksum off (if allowed) + W=2..4 + chunk_size=1MiB + part_size=5MiB
elif need integrity (sha256) + large F:
    async + checksum on + chunk_size=1..8MiB + part_size=5MiB + W sized for RAM
else:
    async + chunk_size=1MiB + part_size=5MiB   # safe default
```

**Do not** expect “5–8 MiB chunks are always faster than 1 MiB” — our local A/B did not support that for e2e latency.

---

## Env knobs in this harness

| Variable | Meaning | Example |
|----------|---------|---------|
| `ASYNC_CHUNK_SIZE` | `AsyncUploader` read size | `1048576` (1 MiB) or `8388608` (8 MiB) |
| `S3_PART_SIZE` | Multipart part size | `5242880` (5 MiB) or `16777216` (16 MiB) |
| `ENABLE_CHECKSUM` | Include SHA-256 validators | `0` / `1` |
| `UVICORN_WORKERS` | Process workers | `4` |

Health JSON reports the active values: `GET /health`.

Reproduce part-size A/B (checksum off, 4 workers, async only):

```bash
cd uploadkit-testing/perf
./scripts/ab_part_size.sh
```

---

## Limitations of this report

- Local MinIO on Docker Desktop — not AWS cross-AZ latency.
- Small iteration counts for PDF A/B (5 reqs); treat ± a few % as noise.
- Async+sync mixed runs inflate averages vs async-only.
- No parallel multipart uploads yet (parts are sequential) — future work may beat size tuning.

When in doubt: **async, `chunk_size=1 MiB`, `part_size=5 MiB`, size workers to concurrency and RAM**, then re-run `scripts/load_k6.sh` on your real target.
