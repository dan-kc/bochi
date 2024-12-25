import { expect } from "@playwright/test";
import {
  createEmailOfLength,
  createPasswordOfLength,
  findErrorByCode,
  RestApiError,
  test,
} from "../../helpers";

test.afterEach(async ({ db }) => {
  await db.deleteAllUsers();
});

test("Create new user", async ({ request }) => {
  const query = {
    email: "daniel@test.com",
    password: "password123",
    confirmPassword: "password123",
  };

  const response = await request.post("/auth/register", {
    data: query,
  });

  const responseBody = await response.json();

  expect(response.ok()).toBeTruthy();
  expect(responseBody.refreshToken).toBeDefined();
  expect(responseBody.accessToken).toBeDefined();
});

test("User already exists", async ({ request, db }) => {
  await db.createUser();

  const query = {
    email: "mock@email.com",
    password: "password123",
    confirmPassword: "password123",
  };

  const response = await request.post("/auth/register", {
    data: query,
  });

  const responseBody = await response.json();
  const errorMessages = responseBody.errors as RestApiError[];

  expect(response.status()).toEqual(409);
  expect(errorMessages.length).toEqual(1);
  expect(errorMessages[0].code).toEqual("USER_ALREADY_EXISTS");
  expect(errorMessages[0].message).toEqual("User already exists.");
});

test("Password too long", async ({ request }) => {
  const pw = createPasswordOfLength(65);
  const query = {
    email: "daniel@test.com",
    password: pw,
    confirmPassword: pw,
  };

  const response = await request.post("/auth/register", {
    data: query,
  });

  const responseBody = await response.json();
  const errorMessages = responseBody.errors as RestApiError[];

  expect(response.status()).toEqual(400);
  expect(errorMessages.length).toEqual(1);
  expect(errorMessages[0].code).toEqual("PASSWORD_TOO_LONG");
  expect(errorMessages[0].message).toEqual(
    "Password too long. The maximum password length is 64.",
  );
});

test("Password not ascii", async ({ request }) => {
  const query = {
    email: "daniel@test.com",
    password: "あ😊あ😊あ😊あ😊あ😊",
    confirmPassword: "あ😊あ😊あ😊あ😊あ😊",
  };

  const response = await request.post("/auth/register", {
    data: query,
  });

  const responseBody = await response.json();
  const errorMessages = responseBody.errors as RestApiError[];

  expect(response.status()).toEqual(400);
  expect(errorMessages.length).toEqual(1);
  expect(errorMessages[0].code).toEqual("PASSWORD_NOT_ASCII");
  expect(errorMessages[0].message).toEqual(
    "Password must contain only standard English letters, numbers, and common punctuation.",
  );
});

test("invalid characters in email", async ({ request }) => {
  const query = {
    email: "[]@hh.com",
    password: "password123",
    confirmPassword: "password123",
  };

  const response = await request.post("/auth/register", {
    data: query,
  });

  const responseBody = await response.json();
  const errorMessages = responseBody.errors as RestApiError[];

  expect(response.status()).toEqual(400);
  expect(errorMessages.length).toEqual(1);
  expect(errorMessages[0].code).toEqual("INVALID_EMAIL_ADDRESS");
  expect(errorMessages[0].message).toEqual("Invalid email address.");
});

test("email too long", async ({ request }) => {
  const query = {
    email: createEmailOfLength(41),
    password: "password123",
    confirmPassword: "password123",
  };

  const response = await request.post("/auth/register", {
    data: query,
  });

  const responseBody = await response.json();
  const errorMessages = responseBody.errors as RestApiError[];

  expect(response.status()).toEqual(400);
  expect(errorMessages.length).toEqual(1);
  expect(errorMessages[0].code).toEqual("EMAIL_TOO_LONG");
  expect(errorMessages[0].message).toEqual(
    "Email too long. The maximum email length is 40.",
  );
});

test("Password too short", async ({ request }) => {
  const query = {
    email: "daniel@test.com",
    password: "passwor",
    confirmPassword: "passwor",
  };

  const response = await request.post("/auth/register", {
    data: query,
  });

  const responseBody = await response.json();
  const errorMessages = responseBody.errors as RestApiError[];

  expect(response.status()).toEqual(400);
  expect(errorMessages.length).toEqual(1);
  expect(errorMessages[0].code).toEqual("PASSWORD_TOO_SHORT");
  expect(errorMessages[0].message).toEqual(
    "Password too short. The min password length is 8.",
  );
});

test("Password mismatch", async ({ request }) => {
  const query = {
    email: "daniel@test.com",
    password: "password123",
    confirmPassword: "password1234",
  };

  const response = await request.post("/auth/register", {
    data: query,
  });

  const responseBody = await response.json();
  const errorMessages = responseBody.errors as RestApiError[];

  expect(response.status()).toEqual(400);
  expect(errorMessages.length).toEqual(1);
  expect(errorMessages[0].code).toEqual("PASSWORD_MISMATCH");
  expect(errorMessages[0].message).toEqual("Passwords do not match.");
});

test("Email too long AND password too long", async ({ request }) => {
  const pw = createPasswordOfLength(65);
  const query = {
    email: createEmailOfLength(41),
    password: pw,
    confirmPassword: pw,
  };

  const response = await request.post("/auth/register", {
    data: query,
  });

  const responseBody = await response.json();
  const errorMessages = responseBody.errors as RestApiError[];

  expect(response.status()).toEqual(400);
  expect(errorMessages.length).toEqual(2);

  const emailError = findErrorByCode("EMAIL_TOO_LONG", errorMessages);
  expect(emailError).toBeTruthy();
  expect(emailError.message).toEqual(
    "Email too long. The maximum email length is 40.",
  );

  const passwordError = findErrorByCode("PASSWORD_TOO_LONG", errorMessages);
  expect(passwordError).toBeTruthy();
  expect(passwordError.message).toEqual(
    "Password too long. The maximum password length is 64.",
  );
});
