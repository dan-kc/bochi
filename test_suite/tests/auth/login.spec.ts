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

  expect(response.status).toEqual(200);
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

  expect(response.status).toEqual(400);
  expect(errorMessages.length).toEqual(1);
  expect(errorMessages[1].code).toEqual("INCORRECT_EMAIL_OR_PASSWORD");
  expect(errorMessages[1].message).toEqual("Incorrect email or password.");
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

  expect(response.status).toEqual(400);
  expect(errorMessages.length).toEqual(1);
  expect(errorMessages[1].code).toEqual("INCORRECT_EMAIL_OR_PASSWORD");
  expect(errorMessages[1].message).toEqual("Incorrect email or password.");
});

test("Should return error for missing fields", async ({ request }) => {
  const response = await request.post("/auth/login", {
    data: {},
  });
  const responseBody = await response.json();
  const errorMessages = responseBody.errors as RestApiError[];

  expect(response.status).toEqual(400);
  expect(errorMessages.length).toEqual(2);

  const emailError = findErrorByCode("MISSING_EMAIL_FIELD", errorMessages);
  expect(emailError).toBeTruthy();
  expect(emailError).toEqual("Missing 'email' field.");

  const passwordError = findErrorByCode(
    "MISSING_PASSWORD_FIELD",
    errorMessages,
  );
  expect(passwordError).toBeTruthy();
  expect(passwordError).toEqual("Missing 'password' field.");
});
