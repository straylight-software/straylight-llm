import { test, expect } from '@playwright/test';

/**
 * Proofs Panel E2E Tests
 * 
 * Tests the discharge proof display and proof API endpoint.
 */

test.describe('Proofs Panel', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('should navigate to proofs tab', async ({ page }) => {
    // Click on Proofs tab
    await page.getByRole('tab', { name: /proofs/i }).click();
    
    // URL should update
    await expect(page).toHaveURL(/\/proofs/);
    
    // Panel should be visible
    await expect(page.getByText(/discharge proof|proofs/i)).toBeVisible();
  });

  test('should display empty state when no requests made', async ({ page }) => {
    await page.getByRole('tab', { name: /proofs/i }).click();
    
    // Should show empty state or proof list
    const emptyState = page.locator('.empty-state');
    const proofList = page.locator('.proof-list, .proof-card');
    
    await expect(emptyState.or(proofList.first())).toBeVisible({ timeout: 10000 });
  });

  test('proof lookup by ID should work', async ({ page }) => {
    // Navigate to a specific proof (may not exist, but route should work)
    await page.goto('/proofs/test-request-id');
    
    // Should either show proof details or "not found" message
    await expect(page.locator('.proof-detail, .error-state, .empty-state')).toBeVisible({ timeout: 5000 });
  });
});

test.describe('Proof API', () => {
  test('proof endpoint should return 404 for non-existent proof', async ({ request }) => {
    const response = await request.get('/v1/proof/nonexistent-request-id');
    expect(response.status()).toBe(404);
  });

  test('proof endpoint should accept valid request ID format', async ({ request }) => {
    // Generate a UUID-like request ID
    const requestId = '550e8400-e29b-41d4-a716-446655440000';
    const response = await request.get(`/v1/proof/${requestId}`);
    
    // Either 404 (not found) or 200 (found) - both are valid responses
    expect([200, 404]).toContain(response.status());
  });
});
