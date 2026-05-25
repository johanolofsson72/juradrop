# Stress testing (pre-deploy)

Stress testing is **MANDATORY** before every deploy — manual or via GitHub Actions. No exceptions. If the system can't handle the load, it doesn't ship.

## When to run

- Before every production deploy (manual or CI/CD)
- After significant performance-related changes (new endpoints, database queries, caching changes)
- When scaling configuration changes (replicas, resource limits)

## Tools

### API stress testing (k6 — preferred)

[k6](https://k6.io/) is the default tool for API load testing. Install via:

```bash
brew install k6          # macOS
# or
docker run --rm -i grafana/k6 run -  # Docker (no install needed)
```

### Frontend stress testing (Lighthouse CI + Playwright)

- **Lighthouse CI** for performance scoring (LCP, FID, CLS, TTFB)
- **Playwright** for simulating concurrent user sessions

## API stress test structure

Create stress tests in `tests/stress/` or `deploy/stress/`:

```javascript
// stress-api.js (k6 script)
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const errorRate = new Rate('errors');
const responseTime = new Trend('response_time');

export const options = {
  stages: [
    { duration: '30s', target: 20 },   // Ramp up to 20 users
    { duration: '1m', target: 50 },    // Hold at 50 users
    { duration: '30s', target: 100 },  // Spike to 100 users
    { duration: '30s', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],   // 95% of requests under 500ms
    errors: ['rate<0.05'],              // Error rate under 5%
    http_req_failed: ['rate<0.05'],     // HTTP failure rate under 5%
  },
};

export default function () {
  // Adapt these endpoints to the actual project
  const baseUrl = __ENV.BASE_URL || 'http://localhost:5000';

  const endpoints = [
    { method: 'GET', url: `${baseUrl}/api/health` },
    // Add project-specific endpoints here
  ];

  for (const endpoint of endpoints) {
    const res = http.request(endpoint.method, endpoint.url, endpoint.body || null, {
      headers: endpoint.headers || { 'Content-Type': 'application/json' },
    });

    check(res, {
      'status is 2xx': (r) => r.status >= 200 && r.status < 300,
      'response time < 500ms': (r) => r.timings.duration < 500,
    });

    errorRate.add(res.status >= 400);
    responseTime.add(res.timings.duration);
  }

  sleep(1);
}
```

Run with:

```bash
k6 run --env BASE_URL=http://localhost:5000 tests/stress/stress-api.js
# or with JSON output for the report:
k6 run --out json=stress-results.json tests/stress/stress-api.js
```

## Frontend stress test structure

```javascript
// stress-frontend.js (k6 browser script)
import { browser } from 'k6/browser';
import { check } from 'k6';

export const options = {
  scenarios: {
    ui: {
      executor: 'shared-iterations',
      iterations: 10,
      vus: 5,
      options: { browser: { type: 'chromium' } },
    },
  },
  thresholds: {
    browser_web_vital_lcp: ['p(95)<2500'],  // Largest Contentful Paint < 2.5s
    browser_web_vital_fid: ['p(95)<100'],   // First Input Delay < 100ms
    browser_web_vital_cls: ['p(95)<0.1'],   // Cumulative Layout Shift < 0.1
  },
};

export default async function () {
  const page = await browser.newPage();
  const baseUrl = __ENV.BASE_URL || 'http://localhost:5000';

  try {
    await page.goto(baseUrl);
    await page.waitForLoadState('networkidle');

    // Add project-specific user flows here
    // e.g., login, navigate, submit forms

    check(page, {
      'page loaded': (p) => p.url() !== 'about:blank',
    });
  } finally {
    await page.close();
  }
}
```

Alternatively, use Lighthouse CI:

```bash
npx @lhci/cli@0.14.x autorun --collect.url=http://localhost:5000
```

## Pass/fail thresholds

| Metric | Threshold | Category |
|--------|-----------|----------|
| p95 response time | < 500ms | API |
| p99 response time | < 2000ms | API |
| Error rate | < 5% | API |
| Requests/sec (sustained) | > 50 rps | API |
| LCP (Largest Contentful Paint) | < 2.5s | Frontend |
| FID (First Input Delay) | < 100ms | Frontend |
| CLS (Cumulative Layout Shift) | < 0.1 | Frontend |
| TTFB (Time to First Byte) | < 800ms | Frontend |

Adjust thresholds per project based on expected traffic and SLAs.

## Report format

After stress testing, generate a report in this format:

```markdown
## Stress Test Report — [Project Name] — [Date]

### API Results
| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| p95 response time | Xms | < 500ms | PASS/FAIL |
| p99 response time | Xms | < 2000ms | PASS/FAIL |
| Error rate | X% | < 5% | PASS/FAIL |
| Total requests | X | — | — |
| Requests/sec (avg) | X | > 50 rps | PASS/FAIL |
| Max concurrent users | X | — | — |

### Frontend Results
| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| LCP | Xs | < 2.5s | PASS/FAIL |
| FID | Xms | < 100ms | PASS/FAIL |
| CLS | X | < 0.1 | PASS/FAIL |
| TTFB | Xms | < 800ms | PASS/FAIL |
| Lighthouse score | X/100 | > 70 | PASS/FAIL |

### Bottlenecks identified
- [List any endpoints or pages that failed thresholds]

### Recommendation
**READY TO DEPLOY** / **NOT READY** (with blocking issues)
```

## CI/CD integration

Add stress testing to the GitHub Actions deploy workflow BEFORE the Docker image push:

```yaml
# In .github/workflows/deploy-[projectname].yml
- name: Stress test API
  run: |
    dotnet run --project src/[ProjectName] &
    sleep 10
    k6 run --env BASE_URL=http://localhost:5000 tests/stress/stress-api.js
    kill %1

- name: Stress test Frontend
  run: |
    npx @lhci/cli@0.14.x autorun --collect.url=http://localhost:5000
```

If k6 thresholds fail, the workflow exits with a non-zero code and the deploy is blocked.
