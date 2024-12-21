import { expect } from "@playwright/test";
import { test } from "../../../helpers";

test.beforeEach(async ({ db }) => {
  await db.createUser();
});

test.afterEach(async ({ db }) => {
  await db.deleteAllUsers();
});

const loginQuery = `
      mutation Login($loginInput: LoginInput) {
          login(input: $loginInput) {
              refreshToken
              accessToken
          }
      }`;

test("Should log in user", async ({ request }) => {
  const query = {
    query: loginQuery,
    variables: {
      loginInput: {
        email: "mock@email.com",
        password: "password123",
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();
  expect(responseBody.data.login.refreshToken).toBeDefined();
  expect(responseBody.data.login.accessToken).toBeDefined();
});

test("Should return error for incorrect email", async ({ request }) => {
  const query = {
    query: loginQuery,
    variables: {
      loginInput: {
        email: "mock2@email.com",
        password: "password123",
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();
  const errorMessages = responseBody.errors.map((error: any) => error.message);
  expect(errorMessages).toContain("Incorrect email or password.");
});

test("Should return error for incorrect password", async ({ request }) => {
  const query = {
    query: loginQuery,
    variables: {
      loginInput: {
        email: "mock@email.com",
        password: "password12",
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();
  const errorMessages = responseBody.errors.map((error: any) => error.message);
  expect(errorMessages).toContain("Incorrect email or password.");
});

test("Should return error for missing password field", async ({ request }) => {
  const query = {
    query: loginQuery,
    variables: {
      loginInput: {
        email: "daniel2@test.com",
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();
  const errorMessages = responseBody.errors.map((error: any) => error.message);
  expect(errorMessages).toContain(
    'Invalid value for argument "input", field "password" of type "String!" is required but not provided',
  );
});
