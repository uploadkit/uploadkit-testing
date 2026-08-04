#!/usr/bin/env sh
# Build a multipart/form-data body file for hey (-D / -T).
# Usage: build_multipart.sh <payload-file> <filename> <content-type> <out-body> <out-ctype>
set -eu

PAYLOAD_FILE="$1"
FILENAME="$2"
CONTENT_TYPE="$3"
OUT_BODY="$4"
OUT_CTYPE="$5"

BOUNDARY="uploadkitperfboundary"

{
  printf -- '--%s\r\n' "${BOUNDARY}"
  printf 'Content-Disposition: form-data; name="file"; filename="%s"\r\n' "${FILENAME}"
  printf 'Content-Type: %s\r\n\r\n' "${CONTENT_TYPE}"
  cat "${PAYLOAD_FILE}"
  printf '\r\n--%s--\r\n' "${BOUNDARY}"
} > "${OUT_BODY}"

printf 'multipart/form-data; boundary=%s' "${BOUNDARY}" > "${OUT_CTYPE}"
