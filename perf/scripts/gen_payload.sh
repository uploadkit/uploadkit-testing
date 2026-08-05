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

# Use Python so magic bytes are written correctly (POSIX printf \xHH is unreliable).
python3 - <<PY
from pathlib import Path

pdf_path = Path("${PDF_PATH}")
png_path = Path("${PNG_PATH}")
pdf_size = ${PDF_SIZE}
png_size = ${PNG_SIZE}

def write_pdf(path: Path, size: int) -> None:
    if path.exists() and path.stat().st_size == size:
        print(f"Reusing existing {path}")
        return
    print(f"Generating {path} ({size} bytes)...")
    header = b"%PDF-1.4\n"
    trailer = b"%%EOF\n"
    pad = size - len(header) - len(trailer)
    if pad < 0:
        raise SystemExit("PDF size too small")
    with path.open("wb") as f:
        f.write(header)
        f.write(b"\x00" * pad)
        f.write(trailer)
    print(f"Wrote {path.stat().st_size} bytes -> {path}")

def write_png(path: Path, size: int) -> None:
    if path.exists() and path.stat().st_size == size:
        print(f"Reusing existing {path}")
        return
    print(f"Generating {path} ({size} bytes)...")
    # PNG signature (8 bytes). MIME sniffers only need the magic for our validators.
    sig = b"\x89PNG\r\n\x1a\n"
    pad = size - len(sig)
    if pad < 0:
        raise SystemExit("PNG size too small")
    with path.open("wb") as f:
        f.write(sig)
        f.write(b"\x00" * pad)
    print(f"Wrote {path.stat().st_size} bytes -> {path}")

write_pdf(pdf_path, pdf_size)
write_png(png_path, png_size)
PY
