import { expect } from "@playwright/test";
import { test } from "../../helpers";

test.beforeEach(async ({ db }) => {
  await db.createUser();
});

test.afterEach(async ({ db }) => {
  await db.executeQuery("DELETE FROM users;");
});

test("Should log out user with valid token", async ({ db, request }) => {
  const query = {
    refreshToken: await db.createRefreshToken("valid"),
  };
  const response = await request.post("/auth/logout", {
    data: query,
  });

  expect(response.status()).toEqual(200);
  const responseBody = await response.json();
  expect(responseBody.success).toBeTruthy;
});

test("Should return success for user with expired token", async ({
  db,
  request,
}) => {
  const query = {
    refreshToken: await db.createRefreshToken("expired"),
  };
  const response = await request.post("/auth/logout", {
    data: query,
  });
  const responseBody = await response.json();

  expect(response.status()).toEqual(200);
  expect(responseBody.success).toBeTruthy;
});
