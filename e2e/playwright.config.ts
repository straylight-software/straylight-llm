import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright configuration for straylight-llm E2E tests
 * 
 * Run with:
 *   npm test              - Run all tests headless
 *   npm run test:headed   - Run with browser visible
 *   npm run test:ui       - Interactive UI mode
 *   npm run codegen       - Record new tests
 */
export default defineConfig({
  testDir: './tests',
  
  // Run tests in parallel
  fullyParallel: true,
  
  // Fail the build on CI if you accidentally left test.only in the source code
  forbidOnly: !!process.env.CI,
  
  // Retry on CI only
  retries: process.env.CI ? 2 : 0,
  
  // Opt out of parallel tests on CI
  workers: process.env.CI ? 1 : undefined,
  
  // Reporter to use
  reporter: [
    ['html', { open: 'never' }],
    ['list'],
  ],
  
  // Shared settings for all tests
  use: {
    // Base URL for the gateway dashboard
    baseURL: process.env.DASHBOARD_URL || 'http://localhost:8080',
    
    // Collect trace when retrying the failed test
    trace: 'on-first-retry',
    
    // Record video on failure
    video: 'on-first-retry',
    
    // Screenshot on failure
    screenshot: 'only-on-failure',
  },

  // Configure projects for major browsers
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
    },
    // Mobile viewports
    {
      name: 'Mobile Chrome',
      use: { ...devices['Pixel 5'] },
    },
    {
      name: 'Mobile Safari',
      use: { ...devices['iPhone 12'] },
    },
  ],

  // Run the gateway before starting the tests
  webServer: {
    command: 'cd .. && nix develop --command bash -c "cd gateway && cabal run straylight-llm"',
    url: 'http://localhost:8080/health',
    reuseExistingServer: !process.env.CI,
    timeout: 120 * 1000,
  },
});
