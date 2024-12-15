import { test, expect } from "@playwright/test";

test("healthcheck", async ({ request }) => {
  const response = await request.get('/health');
  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();
  expect(responseBody).toHaveProperty('healthy', true);
});
