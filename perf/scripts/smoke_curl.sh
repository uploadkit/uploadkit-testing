#!/usr/bin/env sh
# Smoke-test uploads with curl (single request timing per payload/endpoint).
set -eu

API_BASE="${API_BASE:-http://api:8000}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-/artifacts}"
PAYLOAD="${PAYLOAD:-both}"
UPLOAD_ENDPOINT="${UPLOAD_ENDPOINT:-both}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"

mkdir -p "${ARTIFACTS_DIR}"
. "${SCRIPT_DIR}/gen_payload.sh"

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

run_one() {
  endpoint_path="$1"
  label="$2"
  file_path="$3"
  filename="$4"
  mime="$5"
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  out="${ARTIFACTS_DIR}/smoke-${label}-${stamp}.txt"

  echo "=== curl smoke ${label} -> ${endpoint_path} (${filename}) ===" | tee "${out}"
  curl -sS -o "${ARTIFACTS_DIR}/smoke-${label}-body.json" -w \
    "http_code=%{http_code}\nsize_upload=%{size_upload}\ntime_total=%{time_total}\ntime_starttransfer=%{time_starttransfer}\nspeed_upload=%{speed_upload}\n" \
    -F "file=@${file_path};filename=${filename};type=${mime}" \
    "${API_BASE}${endpoint_path}" | tee -a "${out}"
  echo "response:" | tee -a "${out}"
  cat "${ARTIFACTS_DIR}/smoke-${label}-body.json" | tee -a "${out}"
  echo | tee -a "${out}"
}

wait_health

PDF="${ARTIFACTS_DIR}/payloads/fake-100mb.pdf"
PNG="${ARTIFACTS_DIR}/payloads/fake-10mb.png"

should_payload() {
  case "$PAYLOAD" in
    both|all) return 0 ;;
    pdf) [ "$1" = "pdf" ] ;;
    png|image) [ "$1" = "png" ] ;;
    *) return 1 ;;
  esac
}

should_endpoint() {
  case "$UPLOAD_ENDPOINT" in
    both|all) return 0 ;;
    async) [ "$1" = "async" ] ;;
    sync) [ "$1" = "sync" ] ;;
    *) return 1 ;;
  esac
}

if should_payload png; then
  if should_endpoint async; then
    run_one /upload "async-png" "${PNG}" "fake-10mb.png" "image/png"
  fi
  if should_endpoint sync; then
    run_one /upload-sync "sync-png" "${PNG}" "fake-10mb.png" "image/png"
  fi
fi

if should_payload pdf; then
  if should_endpoint async; then
    run_one /upload "async-pdf" "${PDF}" "fake-100mb.pdf" "application/pdf"
  fi
  if should_endpoint sync; then
    run_one /upload-sync "sync-pdf" "${PDF}" "fake-100mb.pdf" "application/pdf"
  fi
fi

echo "Smoke complete. Reports in ${ARTIFACTS_DIR}"
