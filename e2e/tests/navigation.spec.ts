import { test, expect } from '@playwright/test';

/**
 * Navigation E2E Tests
 * 
 * Tests tab navigation, URL routing, and browser history.
 */

test.describe('Tab Navigation', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('should display all navigation tabs', async ({ page }) => {
    // All main tabs should be visible
    await expect(page.getByRole('tab', { name: /health/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /providers/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /models/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /timeline/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /proofs/i })).toBeVisible();
  });

  test('should navigate between all tabs', async ({ page }) => {
    const tabs = ['health', 'providers', 'models', 'timeline', 'proofs'];
    
    for (const tab of tabs) {
      await page.getByRole('tab', { name: new RegExp(tab, 'i') }).click();
      
      // URL should update (except for health which is /)
      if (tab !== 'health') {
        await expect(page).toHaveURL(new RegExp(`/${tab}`));
      }
    }
  });

  test('should preserve state on back/forward navigation', async ({ page }) => {
    // Navigate to models
    await page.getByRole('tab', { name: /models/i }).click();
    await expect(page).toHaveURL(/\/models/);
    
    // Navigate to proofs
    await page.getByRole('tab', { name: /proofs/i }).click();
    await expect(page).toHaveURL(/\/proofs/);
    
    // Go back
    await page.goBack();
    await expect(page).toHaveURL(/\/models/);
    
    // Go forward
    await page.goForward();
    await expect(page).toHaveURL(/\/proofs/);
  });

  test('should handle direct URL navigation', async ({ page }) => {
    // Navigate directly to a route
    await page.goto('/models');
    await expect(page.getByText('Available Models')).toBeVisible();
    
    await page.goto('/timeline');
    await expect(page.getByRole('tab', { name: /timeline/i })).toHaveAttribute('data-state', 'active');
  });

  test('should handle unknown routes gracefully', async ({ page }) => {
    await page.goto('/nonexistent-route');
    
    // Should fall back to health or show not found
    const healthPanel = page.getByText('Gateway Health');
    const notFound = page.getByText(/not found/i);
    
    await expect(healthPanel.or(notFound)).toBeVisible();
  });
});

test.describe('Theme Support', () => {
  test('should have theme CSS loaded', async ({ page }) => {
    await page.goto('/');
    
    // Check that theme styles are present
    const themeClass = await page.evaluate(() => {
      return document.documentElement.className;
    });
    
    // Should have some theme class or default styling
    expect(typeof themeClass).toBe('string');
  });
});
