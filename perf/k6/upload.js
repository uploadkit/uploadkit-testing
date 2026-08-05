import http from "k6/http";
import { check } from "k6";

/**
 * UploadKit FastAPI upload load test (multipart).
 *
 * Env:
 *   API_BASE          default http://127.0.0.1:8000
 *   PAYLOAD           png | pdf | both (default both)
 *   UPLOAD_ENDPOINT   async | sync | both (default both)
 *   K6_VUS_PNG / K6_ITER_PNG   defaults 4 / 20
 *   K6_VUS_PDF / K6_ITER_PDF   defaults 2 / 5
 *   PAYLOADS_DIR      directory with fake-10mb.png / fake-100mb.pdf
 */

const API_BASE = __ENV.API_BASE || "http://127.0.0.1:8000";
const PAYLOAD = (__ENV.PAYLOAD || "both").toLowerCase();
const UPLOAD_ENDPOINT = (__ENV.UPLOAD_ENDPOINT || "both").toLowerCase();
const PAYLOADS_DIR = __ENV.PAYLOADS_DIR || "artifacts/payloads";

const VUS_PNG = Number(__ENV.K6_VUS_PNG || 4);
const ITER_PNG = Number(__ENV.K6_ITER_PNG || 20);
const VUS_PDF = Number(__ENV.K6_VUS_PDF || 2);
const ITER_PDF = Number(__ENV.K6_ITER_PDF || 5);

function wantPayload(kind) {
  return (
    PAYLOAD === "both" ||
    PAYLOAD === "all" ||
    PAYLOAD === kind ||
    (kind === "png" && PAYLOAD === "image")
  );
}

function wantEndpoint(kind) {
  return (
    UPLOAD_ENDPOINT === "both" ||
    UPLOAD_ENDPOINT === "all" ||
    UPLOAD_ENDPOINT === kind
  );
}

const scenarios = {};
if (wantPayload("png") && wantEndpoint("async")) {
  scenarios.png_async = {
    executor: "shared-iterations",
    vus: VUS_PNG,
    iterations: ITER_PNG,
    exec: "uploadPngAsync",
    maxDuration: "30m",
  };
}
if (wantPayload("png") && wantEndpoint("sync")) {
  scenarios.png_sync = {
    executor: "shared-iterations",
    vus: VUS_PNG,
    iterations: ITER_PNG,
    exec: "uploadPngSync",
    maxDuration: "30m",
  };
}
if (wantPayload("pdf") && wantEndpoint("async")) {
  scenarios.pdf_async = {
    executor: "shared-iterations",
    vus: VUS_PDF,
    iterations: ITER_PDF,
    exec: "uploadPdfAsync",
    maxDuration: "60m",
  };
}
if (wantPayload("pdf") && wantEndpoint("sync")) {
  scenarios.pdf_sync = {
    executor: "shared-iterations",
    vus: VUS_PDF,
    iterations: ITER_PDF,
    exec: "uploadPdfSync",
    maxDuration: "60m",
  };
}

if (Object.keys(scenarios).length === 0) {
  throw new Error(
    `No scenarios selected (PAYLOAD=${PAYLOAD}, UPLOAD_ENDPOINT=${UPLOAD_ENDPOINT})`
  );
}

export const options = {
  scenarios,
  thresholds: {
    http_req_failed: ["rate<0.05"],
  },
};

const pngBin = wantPayload("png")
  ? open(`${PAYLOADS_DIR}/fake-10mb.png`, "b")
  : null;
const pdfBin = wantPayload("pdf")
  ? open(`${PAYLOADS_DIR}/fake-100mb.pdf`, "b")
  : null;

function postUpload(path, bin, filename, mime) {
  const res = http.post(
    `${API_BASE}${path}`,
    {
      file: http.file(bin, filename, mime),
    },
    {
      tags: { endpoint: path, filename },
      timeout: "10m",
    }
  );
  check(res, {
    "status is 200": (r) => r.status === 200,
    "has object_name": (r) => {
      try {
        return Boolean(r.json("object_name"));
      } catch (_) {
        return false;
      }
    },
  });
  return res;
}

export function uploadPngAsync() {
  postUpload("/upload", pngBin, "fake-10mb.png", "image/png");
}

export function uploadPngSync() {
  postUpload("/upload-sync", pngBin, "fake-10mb.png", "image/png");
}

export function uploadPdfAsync() {
  postUpload("/upload", pdfBin, "fake-100mb.pdf", "application/pdf");
}

export function uploadPdfSync() {
  postUpload("/upload-sync", pdfBin, "fake-100mb.pdf", "application/pdf");
}
