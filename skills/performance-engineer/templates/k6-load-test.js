// k6 load test template for API endpoints
// Usage: k6 run --env BASE_URL=http://localhost:8000 k6-load-test.js

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const apiLatency = new Trend('api_latency', true);

// Test configuration — adjust stages for your scenario
export const options = {
  stages: [
    // Smoke: verify system works
    { duration: '1m', target: 5 },

    // Ramp up to expected load
    { duration: '3m', target: 50 },

    // Steady state at expected load
    { duration: '5m', target: 50 },

    // Stress: push beyond expected
    { duration: '3m', target: 100 },

    // Sustained stress
    { duration: '5m', target: 100 },

    // Ramp down
    { duration: '2m', target: 0 },
  ],

  thresholds: {
    // SLO-aligned thresholds
    http_req_duration: [
      'p(95)<500',   // 95% of requests under 500ms
      'p(99)<1000',  // 99% under 1s
    ],
    errors: ['rate<0.01'],         // < 1% error rate
    http_req_failed: ['rate<0.01'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';

export default function () {
  group('Health check', () => {
    const res = http.get(`${BASE_URL}/health`);
    check(res, {
      'health: status 200': (r) => r.status === 200,
      'health: latency < 100ms': (r) => r.timings.duration < 100,
    });
  });

  group('List experiments', () => {
    const res = http.get(`${BASE_URL}/api/experiments`);
    check(res, {
      'list: status 200': (r) => r.status === 200,
      'list: latency < 500ms': (r) => r.timings.duration < 500,
      'list: valid JSON': (r) => {
        try { JSON.parse(r.body); return true; } catch { return false; }
      },
    });
    errorRate.add(res.status >= 400);
    apiLatency.add(res.timings.duration);
  });

  group('Get experiment detail', () => {
    const res = http.get(`${BASE_URL}/api/experiments/1`);
    check(res, {
      'detail: status 200 or 404': (r) => [200, 404].includes(r.status),
      'detail: latency < 300ms': (r) => r.timings.duration < 300,
    });
    errorRate.add(res.status >= 500);
    apiLatency.add(res.timings.duration);
  });

  sleep(1);
}
