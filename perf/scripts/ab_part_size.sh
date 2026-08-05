#!/usr/bin/env sh
# A/B: S3 part size 5 MiB vs 16 MiB, checksum off, 4 uvicorn workers.
# Async-only k6 load (part size only affects async multipart).
set -eu

PERF_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "${PERF_DIR}"

export PATH="${HOME}/.local/bin:${PATH}"
export API_BASE="${API_BASE:-http://127.0.0.1:8000}"
export ARTIFACTS_DIR="${ARTIFACTS_DIR:-${PERF_DIR}/artifacts}"
export ENABLE_CHECKSUM=0
export UVICORN_WORKERS=4
export UPLOAD_ENDPOINT=async
export PAYLOAD="${PAYLOAD:-both}"
export K6_VUS_PNG="${K6_VUS_PNG:-4}"
export K6_ITER_PNG="${K6_ITER_PNG:-20}"
export K6_VUS_PDF="${K6_VUS_PDF:-2}"
export K6_ITER_PDF="${K6_ITER_PDF:-5}"

mkdir -p "${ARTIFACTS_DIR}"

run_variant() {
  part_size="$1"
  label="$2"
  echo "======== VARIANT ${label} (S3_PART_SIZE=${part_size}) ========"
  S3_PART_SIZE="${part_size}" ENABLE_CHECKSUM=0 UVICORN_WORKERS=4 \
    docker compose up -d --force-recreate --no-deps api
  i=0
  while [ "$i" -lt 60 ]; do
    if curl -fsS "${API_BASE}/health" >/dev/null 2>&1; then
      break
    fi
    i=$((i + 1))
    sleep 1
  done
  curl -fsS "${API_BASE}/health" | tee "${ARTIFACTS_DIR}/health-${label}.json"
  echo
  PAYLOAD=png UPLOAD_ENDPOINT=async ./scripts/load_k6.sh \
    | tee "${ARTIFACTS_DIR}/ab-${label}-png-console.txt"
  # rename latest k6 outputs with label prefix
  latest_txt="$(ls -1t "${ARTIFACTS_DIR}"/k6-png-async-*.txt | head -1)"
  latest_json="$(ls -1t "${ARTIFACTS_DIR}"/k6-png-async-*.json | head -1)"
  cp "${latest_txt}" "${ARTIFACTS_DIR}/ab-${label}-png.txt"
  cp "${latest_json}" "${ARTIFACTS_DIR}/ab-${label}-png.json"

  PAYLOAD=pdf UPLOAD_ENDPOINT=async ./scripts/load_k6.sh \
    | tee "${ARTIFACTS_DIR}/ab-${label}-pdf-console.txt"
  latest_txt="$(ls -1t "${ARTIFACTS_DIR}"/k6-pdf-async-*.txt | head -1)"
  latest_json="$(ls -1t "${ARTIFACTS_DIR}"/k6-pdf-async-*.json | head -1)"
  cp "${latest_txt}" "${ARTIFACTS_DIR}/ab-${label}-pdf.txt"
  cp "${latest_json}" "${ARTIFACTS_DIR}/ab-${label}-pdf.json"
}

# Rebuild once with latest app code
DOCKER_BUILDKIT=1 docker compose build --pull=false api

run_variant 5242880 part5m
run_variant 16777216 part16m

python3 - <<'PY'
import json
from pathlib import Path

arts = Path("artifacts")

def summarize(label, payload):
    p = arts / f"ab-{label}-{payload}.json"
    d = json.loads(p.read_text())
    m = d["metrics"]
    dur = m["http_req_duration"]["values"]
    wait = m["http_req_waiting"]["values"]
    send = m["http_req_sending"]["values"]
    reqs = m["http_reqs"]["values"]
    failed = m["http_req_failed"]["values"]
    return {
        "avg_ms": dur["avg"],
        "med_ms": dur["med"],
        "p90_ms": dur["p(90)"],
        "p95_ms": dur["p(95)"],
        "wait_avg_ms": wait["avg"],
        "send_avg_ms": send["avg"],
        "req_rate": reqs["rate"],
        "fail_rate": failed.get("rate", 0),
        "checks_pass": d["root_group"]["checks"]["status is 200"]["passes"],
        "checks_fail": d["root_group"]["checks"]["status is 200"]["fails"],
    }

rows = []
for label in ("part5m", "part16m"):
    for payload in ("png", "pdf"):
        s = summarize(label, payload)
        rows.append((label, payload, s))

print("\n=== A/B SUMMARY (checksum=off, workers=4, async-only) ===")
print(f"{'variant':<10} {'payload':<6} {'avg_s':>8} {'med_s':>8} {'p90_s':>8} {'wait_s':>8} {'send_s':>8} {'rps':>8} {'fail%':>7} {'ok':>5}")
for label, payload, s in rows:
    print(
        f"{label:<10} {payload:<6} "
        f"{s['avg_ms']/1000:8.2f} {s['med_ms']/1000:8.2f} {s['p90_ms']/1000:8.2f} "
        f"{s['wait_avg_ms']/1000:8.2f} {s['send_avg_ms']/1000:8.2f} "
        f"{s['req_rate']:8.3f} {s['fail_rate']*100:6.1f}% "
        f"{s['checks_pass']}/{s['checks_pass']+s['checks_fail']}"
    )

# relative change part16 vs part5
print("\n=== part16m vs part5m (negative = faster) ===")
for payload in ("png", "pdf"):
    a = summarize("part5m", payload)
    b = summarize("part16m", payload)
    def pct(new, old):
        return (new - old) / old * 100
    print(
        f"{payload}: avg {pct(b['avg_ms'], a['avg_ms']):+.1f}%, "
        f"wait {pct(b['wait_avg_ms'], a['wait_avg_ms']):+.1f}%, "
        f"send {pct(b['send_avg_ms'], a['send_avg_ms']):+.1f}%, "
        f"rps {pct(b['req_rate'], a['req_rate']):+.1f}%"
    )
PY
