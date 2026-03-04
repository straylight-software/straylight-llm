import { test, expect } from '@playwright/test';

/**
 * Models Panel E2E Tests
 * 
 * Tests the available models display and model listing API.
 */

test.describe('Models Panel', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('should navigate to models tab', async ({ page }) => {
    // Click on Models tab
    await page.getByRole('tab', { name: /models/i }).click();
    
    // URL should update
    await expect(page).toHaveURL(/\/models/);
    
    // Panel should be visible
    await expect(page.getByText('Available Models')).toBeVisible();
  });

  test('should display model count badge', async ({ page }) => {
    await page.getByRole('tab', { name: /models/i }).click();
    
    // Wait for models to load
    await expect(page.locator('.panel-badge')).toBeVisible({ timeout: 15000 });
    
    // Badge should show model count
    await expect(page.locator('.panel-badge')).toContainText(/\d+ models/);
  });

  test('should list models with provider info', async ({ page }) => {
    await page.getByRole('tab', { name: /models/i }).click();
    
    // Wait for model list
    await expect(page.locator('.model-card, .model-row, .model-item').first()).toBeVisible({ timeout: 15000 });
  });

  test('models API endpoint should respond', async ({ request }) => {
    const response = await request.get('/v1/models');
    expect(response.ok()).toBeTruthy();
    
    const body = await response.json();
    expect(body).toHaveProperty('data');
    expect(body).toHaveProperty('object', 'list');
    expect(Array.isArray(body.data)).toBeTruthy();
  });

  test('models should have required OpenAI fields', async ({ request }) => {
    const response = await request.get('/v1/models');
    const body = await response.json();
    
    if (body.data.length > 0) {
      const model = body.data[0];
      expect(model).toHaveProperty('id');
      expect(model).toHaveProperty('object', 'model');
      expect(model).toHaveProperty('owned_by');
    }
  });
});
