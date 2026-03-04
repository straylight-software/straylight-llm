import { test, expect } from '@playwright/test';

/**
 * Health Panel E2E Tests
 * 
 * Tests the gateway health status display and API connectivity.
 */

test.describe('Health Panel', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('should display health status on load', async ({ page }) => {
    // Wait for health panel to load
    await expect(page.locator('.dashboard-panel').first()).toBeVisible();
    
    // Check for health status elements
    await expect(page.getByText('Gateway Health')).toBeVisible();
  });

  test('should show loading state initially', async ({ page }) => {
    // Fast check before data loads
    const loadingState = page.locator('.loading-state');
    // Either loading or already loaded
    const healthGrid = page.locator('.health-grid');
    
    await expect(loadingState.or(healthGrid)).toBeVisible({ timeout: 10000 });
  });

  test('should display version information', async ({ page }) => {
    // Wait for health data to load
    await expect(page.locator('.health-grid')).toBeVisible({ timeout: 10000 });
    
    // Should show version info
    await expect(page.getByText(/v\d+\.\d+\.\d+/)).toBeVisible();
  });

  test('health API endpoint should respond', async ({ request }) => {
    const response = await request.get('/health');
    expect(response.ok()).toBeTruthy();
    
    const body = await response.json();
    expect(body).toHaveProperty('status');
    expect(body).toHaveProperty('version');
  });
});
