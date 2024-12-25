import { test, expect } from "@playwright/test";

test("healthcheck", async ({ request }) => {
  const response = await request.get('/health');
  const responseBody = await response.json();

  expect(response.status()).toEqual(200);
  expect(responseBody).toHaveProperty('healthy', true);
});
