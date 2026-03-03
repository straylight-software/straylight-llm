import { test, expect } from '@playwright/test';

/**
 * SSE Events E2E Tests
 * 
 * Tests the real-time Server-Sent Events endpoint.
 */

test.describe('SSE Events Endpoint', () => {
  test('should connect to events endpoint', async ({ request }) => {
    const response = await request.get('/v1/events', {
      headers: {
        'Accept': 'text/event-stream'
      }
    });
    
    expect(response.ok()).toBeTruthy();
    
    const contentType = response.headers()['content-type'];
    expect(contentType).toContain('text/event-stream');
  });

  test('should receive keepalive events', async ({ page }) => {
    // Create an EventSource connection via page context
    const events: string[] = [];
    
    await page.goto('/');
    
    // Set up SSE listener
    const eventPromise = page.evaluate(() => {
      return new Promise<string>((resolve) => {
        const es = new EventSource('/v1/events');
        es.onmessage = (event) => {
          es.close();
          resolve(event.data);
        };
        es.onerror = () => {
          es.close();
          resolve('error');
        };
        // Timeout after 10 seconds
        setTimeout(() => {
          es.close();
          resolve('timeout');
        }, 10000);
      });
    });
    
    const result = await eventPromise;
    
    // Should receive some event (keepalive, or other)
    expect(['timeout', 'error']).not.toContain(result);
  });
});

test.describe('Events Page Integration', () => {
  test('should show real-time updates in dashboard', async ({ page }) => {
    await page.goto('/');
    
    // Dashboard should be visible and loading data
    await expect(page.locator('.dashboard-panel').first()).toBeVisible();
    
    // Make a request that should generate events
    // (health check is already happening on load)
    
    // Timeline should eventually show activity or empty state
    await page.getByRole('tab', { name: /timeline/i }).click();
    await expect(page.locator('.timeline-container, .empty-state')).toBeVisible({ timeout: 10000 });
  });
});
