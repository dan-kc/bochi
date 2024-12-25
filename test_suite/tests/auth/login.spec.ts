import { expect } from "@playwright/test";
import { findErrorByCode, RestApiError, test } from "../../helpers";

test.beforeEach(async ({ db }) => {
  await db.createUser();
});

test.afterEach(async ({ db }) => {
  await db.deleteAllUsers();
});

test("Should log in user", async ({ request }) => {
  const query = {
    email: "mock@email.com",
    password: "password123",
  };
  const response = await request.post("/auth/login", {
    data: query,
  });
  const responseBody = await response.json();

  expect(response.status()).toEqual(200);
  expect(responseBody.refreshToken).toBeDefined();
  expect(responseBody.accessToken).toBeDefined();
});

test("Should return error for non-existent email", async ({ request }) => {
  const query = {
    email: "mock2@email.com",
    password: "password123",
  };

  const response = await request.post("/auth/login", {
    data: query,
  });
  const responseBody = await response.json();
  const errorMessages = responseBody.errors as RestApiError[];

  expect(response.status()).toEqual(401);
  expect(errorMessages.length).toEqual(1);
  expect(errorMessages[0].code).toEqual("INVALID_LOGIN_CREDENTIALS");
  expect(errorMessages[0].message).toEqual("Incorrect email or password.");
});

test("Should return error for incorrect password", async ({ request }) => {
  const query = {
    email: "mock@email.com",
    password: "password12",
  };
  const response = await request.post("/auth/login", {
    data: query,
  });
  const responseBody = await response.json();
  const errorMessages = responseBody.errors as RestApiError[];

  expect(response.status()).toEqual(401);
  expect(errorMessages.length).toEqual(1);
  expect(errorMessages[0].code).toEqual("INVALID_LOGIN_CREDENTIALS");
  expect(errorMessages[0].message).toEqual("Incorrect email or password.");
});
