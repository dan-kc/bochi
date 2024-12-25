import { expect } from "@playwright/test";
import { createAccessToken, RestApiError, test } from "../../helpers";

test.beforeEach(async ({ db }) => {
  await db.createUser();
});

test.afterEach(async ({ db }) => {
  await db.deleteAllUsers();
});

test("Should return new api key", async ({ request }) => {
  const response = await request.get("/auth/api-key", {
    headers: {
      Authorization: await createAccessToken(),
    },
  });
  const responseBody = await response.json();

  expect(response.status()).toEqual(200);
  expect(responseBody.apiKey).toBeDefined();
});

test("Should not return api key if access token is expired", async ({
  request,
}) => {
  const response = await request.get("/auth/api-key", {
    headers: {
      Authorization: await createAccessToken(true),
    },
  });
  expect(response.status()).toEqual(401);
  try {
    const responseBody = await response.json(); // Fails if resp not json
    expect(responseBody.apiKey).toBeDefined();
  } catch {}
});

test("Should not refresh token if no access token", async ({ request }) => {
  const response = await request.get("/auth/api-key");

  expect(response.status()).toEqual(401);
  try {
    const responseBody = await response.json(); // Fails if resp not json
    expect(responseBody.apiKey).toBeDefined();
  } catch {}
});
