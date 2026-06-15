# Stress testing (pre-deploy)

Stress testing is **MANDATORY** before every deploy — manual or via GitHub Actions. No exceptions. If the system can't handle the load, it doesn't ship.

> **Web vs mobile.** The k6 + Lighthouse sections below are for **web/.NET backends and frontends** — load-testing an API and measuring web vitals in a browser. A native mobile app has no server to hammer and no browser to Lighthouse; its performance budget is on-device (frame rate, startup, memory). For React Native / Expo and Flutter, use the **Native app performance** section near the end of this doc instead. A mobile project still stress-tests any backend it talks to with k6 (that backend lives on live4 and ships via `deployment.md`).

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

## Native app performance (React Native / Expo · Flutter)

A mobile app does not get "stress tested" with concurrent virtual users — it gets profiled on a real device for the things that make an app feel cheap: dropped frames, slow cold start, and runaway memory. Run these on a **release/profile build on a physical mid-tier device**, not a flagship simulator (the simulator hides jank).

### What to measure

| Metric | Budget | Why |
|---|---|---|
| **Frame rate (scroll/animation)** | sustained 60fps; **0 frames > 16ms** on a hot path | jank is the #1 "feels cheap" signal — lists, maps, transitions |
| **Cold start** (process start → first interactive screen) | < 2.5s mid-tier device | first impression; store ranking signal |
| **Warm start** (background → foreground) | < 1s | lifecycle resume must feel instant |
| **JS thread / UI thread** | never blocked > 100ms | a blocked thread = frozen taps |
| **Memory (steady state + after heavy nav)** | no unbounded growth; no OOM on a 3GB device | leaks crash low-end devices first |
| **Bundle / app size** | track per release, justify increases | download abandonment, store limits |
| **Large list scroll** | 10k rows, no jank, no OOM | the FlatList/FlashList/`ListView.builder` stress case |

### Tools

**React Native / Expo**
- **React Native DevTools** — the default debugger since RN 0.76, with the **Performance Panel** (JS-thread profiling, flame charts) since RN 0.83. This is the modern profiler. *(Flipper was deprecated in RN 0.74 and Meta wound down OSS Flipper in late 2024 — do NOT use it.)*
- In-app **Perf Monitor** (`Dev Menu → Show Perf Monitor`) for a live JS/UI fps readout, plus the **Hermes Sampling Profiler** (flame graphs over the Chrome DevTools protocol) and the **React DevTools Profiler** for re-render analysis.
- **`react-native-performance`** for marking startup/interaction timings programmatically — surfaced via **Rozenite** (the RN DevTools plugin host), not the dead Flipper plugin.
- **Reassure** for render-performance *regression* tests in CI-adjacent runs (catches a component that got 3× slower).

**Flutter**
- `flutter run --profile` + **DevTools → Performance** timeline; watch for red "jank" frames in the timeline.
- `flutter run --profile --trace-startup` writes `start_up_info.json` (engine init → first frame → first useful frame).
- DevTools **Memory** view for leak/retention; **CPU profiler** for hot functions.
- An `integration_test` driven with `IntegrationTestWidgetsFlutterBinding` + `traceAction` produces a `timeline_summary` with `missed_frames` counts — assert on it.

### Pass/fail

A mobile build is NOT ready to ship if: scroll on the heaviest screen drops frames, cold start exceeds 2.5s on a mid-tier device, memory grows without bound across repeated navigation, or a 10k-item list janks/OOMs. Record the numbers in the report (same format as below — substitute the native metrics for the web vitals rows).

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
