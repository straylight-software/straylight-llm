# Straylight E2E Tests

End-to-end tests for the straylight-llm gateway dashboard using Playwright.

## Setup

```bash
cd e2e
npm install
npx playwright install  # Install browsers
```

## Running Tests

```bash
# Run all tests (headless)
npm test

# Run with browser visible
npm run test:headed

# Interactive UI mode (recommended for debugging)
npm run test:ui

# Debug mode (step through tests)
npm run test:debug

# Run specific test file
npx playwright test tests/health.spec.ts

# Run tests matching pattern
npx playwright test -g "should display health"
```

## Recording New Tests

Playwright's codegen tool records your browser interactions and generates test code:

```bash
# Start recording (gateway must be running)
npm run codegen

# Record with authentication state saved
npm run record
```

This opens a browser and records your actions. Copy the generated code into a test file.

## Test Structure

```
e2e/
├── package.json           # Dependencies and scripts
├── playwright.config.ts   # Playwright configuration
├── README.md              # This file
└── tests/
    ├── health.spec.ts     # Health panel tests
    ├── models.spec.ts     # Models panel tests
    ├── proofs.spec.ts     # Proofs panel tests
    ├── navigation.spec.ts # Tab navigation tests
    ├── chat-api.spec.ts   # Chat completions API tests
    └── sse-events.spec.ts # Real-time events tests
```

## Configuration

The tests connect to `http://localhost:8080` by default. Override with:

```bash
DASHBOARD_URL=http://localhost:3000 npm test
```

The `playwright.config.ts` includes a `webServer` configuration that automatically starts the gateway before tests (on CI) or reuses an existing server (local development).

## Reports

After running tests, view the HTML report:

```bash
npm run show-report
```

Reports are also generated in `playwright-report/` directory.

## CI Integration

Tests run automatically in CI with:
- Retry on failure (2 retries)
- Video recording on first retry
- Screenshots on failure
- Trace collection for debugging

## Browser Coverage

Tests run on:
- Chromium (Desktop Chrome)
- Firefox (Desktop Firefox)  
- WebKit (Desktop Safari)
- Mobile Chrome (Pixel 5)
- Mobile Safari (iPhone 12)

Run specific browser:

```bash
npx playwright test --project=chromium
npx playwright test --project=firefox
npx playwright test --project="Mobile Safari"
```

## Writing Tests

### Page Object Pattern

For complex pages, consider creating page objects:

```typescript
// pages/dashboard.ts
export class DashboardPage {
  constructor(private page: Page) {}
  
  async navigateToModels() {
    await this.page.getByRole('tab', { name: /models/i }).click();
  }
  
  async getModelCount() {
    const badge = this.page.locator('.panel-badge');
    const text = await badge.textContent();
    return parseInt(text?.match(/\d+/)?.[0] || '0');
  }
}
```

### API Testing

Use `request` fixture for direct API calls:

```typescript
test('API returns valid response', async ({ request }) => {
  const response = await request.get('/v1/models');
  expect(response.ok()).toBeTruthy();
});
```

### Visual Regression

Add screenshot comparisons:

```typescript
test('dashboard looks correct', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveScreenshot('dashboard.png');
});
```

## Troubleshooting

### Tests timeout waiting for gateway

Ensure the gateway is running:
```bash
cd ../gateway && cabal run straylight-llm
```

### Browser installation issues

```bash
npx playwright install --with-deps
```

### Flaky tests

Use `test.retry(3)` for flaky tests or increase timeouts:

```typescript
test('slow operation', async ({ page }) => {
  test.setTimeout(60000);
  // ...
});
```
