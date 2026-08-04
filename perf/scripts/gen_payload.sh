#!/usr/bin/env sh
# Generate fake PDF (100 MB) and PNG (10 MB) payloads with correct magic bytes.
set -eu

ARTIFACTS_DIR="${ARTIFACTS_DIR:-/artifacts}"
PAYLOADS_DIR="${ARTIFACTS_DIR}/payloads"
mkdir -p "${PAYLOADS_DIR}"

PDF_PATH="${PAYLOADS_DIR}/fake-100mb.pdf"
PNG_PATH="${PAYLOADS_DIR}/fake-10mb.png"
PDF_SIZE=$((100 * 1024 * 1024))
PNG_SIZE=$((10 * 1024 * 1024))

if [ ! -f "${PDF_PATH}" ] || [ "$(wc -c < "${PDF_PATH}")" -ne "${PDF_SIZE}" ]; then
  echo "Generating ${PDF_PATH} (${PDF_SIZE} bytes)..."
  dd if=/dev/zero of="${PDF_PATH}.tmp" bs=1M count=100 status=none
  printf '%%PDF-1.4\n' | dd of="${PDF_PATH}.tmp" conv=notrunc status=none
  printf '%%%%EOF\n' | dd of="${PDF_PATH}.tmp" bs=1 seek=$((PDF_SIZE - 6)) conv=notrunc status=none
  mv "${PDF_PATH}.tmp" "${PDF_PATH}"
  echo "Wrote $(wc -c < "${PDF_PATH}") bytes -> ${PDF_PATH}"
else
  echo "Reusing existing ${PDF_PATH}"
fi

if [ ! -f "${PNG_PATH}" ] || [ "$(wc -c < "${PNG_PATH}")" -ne "${PNG_SIZE}" ]; then
  echo "Generating ${PNG_PATH} (${PNG_SIZE} bytes)..."
  dd if=/dev/zero of="${PNG_PATH}.tmp" bs=1M count=10 status=none
  printf '\x89PNG\r\n\x1a\n' | dd of="${PNG_PATH}.tmp" conv=notrunc status=none
  mv "${PNG_PATH}.tmp" "${PNG_PATH}"
  echo "Wrote $(wc -c < "${PNG_PATH}") bytes -> ${PNG_PATH}"
else
  echo "Reusing existing ${PNG_PATH}"
fi
