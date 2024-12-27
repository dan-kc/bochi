import { expect } from "@playwright/test";
import { RestApiError, test } from "../../helpers";

test.beforeEach(async ({ db }) => {
  await db.createUser();
});

test.afterEach(async ({ db }) => {
  await db.deleteAllUsers();
});

test("Should return new tokens", async ({ db, request }) => {
  const response = await request.post("/auth/refresh-tokens", {
    data: {
      refreshToken: await db.createRefreshToken("valid"),
    },
  });
  const responseBody = await response.json();

  expect(response.status()).toEqual(200);
  expect(responseBody.refreshToken).toBeDefined();
  expect(responseBody.accessToken).toBeDefined();
});

test("Should not refresh token if expired", async ({ db, request }) => {
  const response = await request.post("/auth/refresh-tokens", {
    data: {
      refreshToken: await db.createRefreshToken("expired"),
    },
  });
  const responseBody = await response.json();
  const errorMessages = responseBody.errors as RestApiError[];

  expect(response.status()).toEqual(401);
  expect(errorMessages.length).toEqual(1);
  expect(errorMessages[0].code).toEqual("INVALID_REFRESH_TOKEN");
  expect(errorMessages[0].message).toEqual("Invalid refresh token.");
});

test("Should not refresh token if wrong uuid", async ({ request }) => {
  const response = await request.post("/auth/refresh-tokens", {
    data: {
      refreshToken: "b7eab812_9b9a_4823_930d_38c3c891ea8d",
    },
  });
  const responseBody = await response.json();
  const errorMessages = responseBody.errors as RestApiError[];

  expect(response.status()).toEqual(401);
  expect(errorMessages.length).toEqual(1);
  expect(errorMessages[0].code).toEqual("INVALID_REFRESH_TOKEN");
  expect(errorMessages[0].message).toEqual("Invalid refresh token.");
});
