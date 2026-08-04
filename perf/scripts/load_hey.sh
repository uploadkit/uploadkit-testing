#!/usr/bin/env sh
# Concurrent upload load with hey against async and/or sync endpoints.
set -eu

API_BASE="${API_BASE:-http://api:8000}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-/artifacts}"
PAYLOAD="${PAYLOAD:-both}"
UPLOAD_ENDPOINT="${UPLOAD_ENDPOINT:-both}"
HEY_N_PNG="${HEY_N_PNG:-50}"
HEY_C_PNG="${HEY_C_PNG:-5}"
HEY_N_PDF="${HEY_N_PDF:-10}"
HEY_C_PDF="${HEY_C_PDF:-2}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"

mkdir -p "${ARTIFACTS_DIR}/multipart"
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

run_hey() {
  endpoint_path="$1"
  label="$2"
  body="$3"
  ctype_file="$4"
  n="$5"
  c="$6"
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  out="${ARTIFACTS_DIR}/hey-${label}-${stamp}.txt"
  ctype="$(cat "${ctype_file}")"

  echo "=== hey ${label} n=${n} c=${c} -> ${endpoint_path} ===" | tee "${out}"
  hey -n "${n}" -c "${c}" -m POST \
    -T "${ctype}" \
    -D "${body}" \
    "${API_BASE}${endpoint_path}" | tee -a "${out}"
  echo | tee -a "${out}"
}

wait_health

PDF="${ARTIFACTS_DIR}/payloads/fake-100mb.pdf"
PNG="${ARTIFACTS_DIR}/payloads/fake-10mb.png"
MP_DIR="${ARTIFACTS_DIR}/multipart"

if should_payload png; then
  sh "${SCRIPT_DIR}/build_multipart.sh" \
    "${PNG}" "fake-10mb.png" "image/png" \
    "${MP_DIR}/png.body" "${MP_DIR}/png.ctype"
  if should_endpoint async; then
    run_hey /upload "async-png" "${MP_DIR}/png.body" "${MP_DIR}/png.ctype" "${HEY_N_PNG}" "${HEY_C_PNG}"
  fi
  if should_endpoint sync; then
    run_hey /upload-sync "sync-png" "${MP_DIR}/png.body" "${MP_DIR}/png.ctype" "${HEY_N_PNG}" "${HEY_C_PNG}"
  fi
fi

if should_payload pdf; then
  sh "${SCRIPT_DIR}/build_multipart.sh" \
    "${PDF}" "fake-100mb.pdf" "application/pdf" \
    "${MP_DIR}/pdf.body" "${MP_DIR}/pdf.ctype"
  if should_endpoint async; then
    run_hey /upload "async-pdf" "${MP_DIR}/pdf.body" "${MP_DIR}/pdf.ctype" "${HEY_N_PDF}" "${HEY_C_PDF}"
  fi
  if should_endpoint sync; then
    run_hey /upload-sync "sync-pdf" "${MP_DIR}/pdf.body" "${MP_DIR}/pdf.ctype" "${HEY_N_PDF}" "${HEY_C_PDF}"
  fi
fi

echo "Load complete. Reports in ${ARTIFACTS_DIR}"
