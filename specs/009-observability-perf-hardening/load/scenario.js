import http from "k6/http";
import { check } from "k6";
import encoding from "k6/encoding";

// Configurable via env vars:
//   BASE_URL      — default http://app:3000
//   DURATION      — default 1h (use 5m for baseline)
//   TARGET_RPS    — default 140
//   LT_USER       — LOAD_TEST_BASIC_AUTH_USER
//   LT_PASSWORD   — LOAD_TEST_BASIC_AUTH_PASSWORD

const BASE_URL   = __ENV.BASE_URL   || "http://app:3000";
const DURATION   = __ENV.DURATION   || "1h";
const TARGET_RPS = parseInt(__ENV.TARGET_RPS || "140");
const LT_USER    = __ENV.LT_USER    || "loadtest";
const LT_PASSWORD = __ENV.LT_PASSWORD || "loadtest";

const INGEST_URL = `${BASE_URL}/internal/ingest`;
const AUTH_HEADER = `Basic ${encoding.b64encode(`${LT_USER}:${LT_PASSWORD}`)}`;

export const options = {
  scenarios: {
    constant_load: {
      executor: "constant-arrival-rate",
      rate: TARGET_RPS,
      timeUnit: "1s",
      duration: DURATION,
      preAllocatedVUs: 50,
      maxVUs: 200,
    },
  },
  thresholds: {
    http_req_duration: [`p(95)<200`],
    http_req_failed: ["rate<0.01"],
  },
};

let counter = 0;

export default function () {
  counter++;
  const contextId = `lt-${__VU}-${__ITER}-${counter}`;

  const payload = JSON.stringify({
    recipient: `loadtest+${contextId}@example.com`,
    context_id: contextId,
  });

  const res = http.post(INGEST_URL, payload, {
    headers: {
      "Content-Type": "application/json",
      Authorization: AUTH_HEADER,
    },
    timeout: "5s",
  });

  check(res, {
    "status 2xx": (r) => r.status >= 200 && r.status < 300,
  });
}
