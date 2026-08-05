#!/usr/bin/env sh
# Run k6 multipart upload load tests. Requires k6 on PATH (host or container).
set -eu

API_BASE="${API_BASE:-http://127.0.0.1:8000}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-/artifacts}"
PAYLOAD="${PAYLOAD:-both}"
UPLOAD_ENDPOINT="${UPLOAD_ENDPOINT:-both}"
K6_VUS_PNG="${K6_VUS_PNG:-4}"
K6_ITER_PNG="${K6_ITER_PNG:-20}"
K6_VUS_PDF="${K6_VUS_PDF:-2}"
K6_ITER_PDF="${K6_ITER_PDF:-5}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
PERF_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
K6_SCRIPT="${PERF_DIR}/k6/upload.js"

mkdir -p "${ARTIFACTS_DIR}"
. "${SCRIPT_DIR}/gen_payload.sh"

if ! command -v k6 >/dev/null 2>&1; then
  echo "k6 not found on PATH. Install from https://grafana.com/docs/k6/latest/set-up/install-k6/" >&2
  exit 1
fi

wait_health() {
  i=0
  while [ "$i" -lt 60 ]; do
    if curl -fsS "${API_BASE}/health" >/dev/null 2>&1; then
      echo "API healthy at ${API_BASE}"
      return 0
    fi
    i=$((i + 1))
    sleep 1
  done
  echo "API did not become healthy at ${API_BASE}" >&2
  exit 1
}

wait_health

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="${ARTIFACTS_DIR}/k6-${PAYLOAD}-${UPLOAD_ENDPOINT}-${stamp}.txt"
json_out="${ARTIFACTS_DIR}/k6-${PAYLOAD}-${UPLOAD_ENDPOINT}-${stamp}.json"

# k6 open() paths are relative to the process CWD
cd "${PERF_DIR}"

echo "=== k6 load PAYLOAD=${PAYLOAD} ENDPOINT=${UPLOAD_ENDPOINT} ===" | tee "${out}"
echo "API_BASE=${API_BASE}" | tee -a "${out}"
echo "VUS/ITER png=${K6_VUS_PNG}/${K6_ITER_PNG} pdf=${K6_VUS_PDF}/${K6_ITER_PDF}" | tee -a "${out}"

API_BASE="${API_BASE}" \
PAYLOAD="${PAYLOAD}" \
UPLOAD_ENDPOINT="${UPLOAD_ENDPOINT}" \
PAYLOADS_DIR="${ARTIFACTS_DIR}/payloads" \
K6_VUS_PNG="${K6_VUS_PNG}" \
K6_ITER_PNG="${K6_ITER_PNG}" \
K6_VUS_PDF="${K6_VUS_PDF}" \
K6_ITER_PDF="${K6_ITER_PDF}" \
  k6 run \
    --summary-export "${json_out}" \
    "${K6_SCRIPT}" | tee -a "${out}"

echo "Load complete. Report: ${out}"
echo "Summary JSON: ${json_out}"
