import { expect } from "@playwright/test";
import { test } from "../../../../helpers";

test.afterEach(async ({ db }) => {
  await db.deleteAllUsers();
});

const createUserQuery = `
      mutation CreateUser($createUserInput: CreateUserInput) {
          createUser(input: $createUserInput) {
              refreshToken
              accessToken
          }
      }`;

test("Create new user", async ({ request }) => {
  const query = {
    query: createUserQuery,
    variables: {
      createUserInput: {
        email: "daniel@test.com",
        password: "password123",
        confirmPassword: "password123",
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();
  expect(responseBody.data.createUser.refreshToken).toBeDefined();
  expect(responseBody.data.createUser.accessToken).toBeDefined();
});

test("User already exists", async ({ request, db }) => {
  await db.createUser();

  const query = {
    query: createUserQuery,
    variables: {
      createUserInput: {
        email: "mock@email.com",
        password: "password123",
        confirmPassword: "password123",
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();
  const errorMessages = responseBody.errors.map((error: any) => error.message);
  expect(errorMessages).toContain("User already exists.");
});

test("Password too long", async ({ request }) => {
  const query = {
    query: createUserQuery,
    variables: {
      createUserInput: {
        email: "daniel@test.com",
        password:
          "01234567890123456789012345678901234567980123456789012345678901234",
        confirmPassword:
          "01234567890123456789012345678901234567980123456789012345678901234",
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
    "Password too long. The max password length is 64.",
  );
});

test("Password not ascii", async ({ request }) => {
  const query = {
    query: createUserQuery,
    variables: {
      createUserInput: {
        email: "daniel2@test.com",
        password: "あ😊あ😊あ😊あ😊あ😊",
        confirmPassword: "あ😊あ😊あ😊あ😊あ😊",
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
    "Password must contain only standard English letters, numbers, and common punctuation.",
  );
});

test("invalid email", async ({ request }) => {
  const query = {
    query: createUserQuery,
    variables: {
      createUserInput: {
        email: "[]@hh.com",
        password: "password123",
        confirmPassword: "password123",
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();
  const errorMessages = responseBody.errors.map((error: any) => error.message);
  expect(errorMessages).toContain("Invalid email address.");
});

test("email too long", async ({ request }) => {
  const query = {
    query: createUserQuery,
    variables: {
      createUserInput: {
        email: "0123456789012345678901234567890123@hh.com",
        password: "password123",
        confirmPassword: "password123",
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
    "Email too long. The max email length is 40.",
  );
});

test("Password too short", async ({ request }) => {
  const query = {
    query: createUserQuery,
    variables: {
      createUserInput: {
        email: "daniel@test.com",
        password: "passwor",
        confirmPassword: "passwor",
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
    "Password too short. The min password length is 8.",
  );
});

test("Password mismatch", async ({ request }) => {
  const query = {
    query: createUserQuery,
    variables: {
      createUserInput: {
        email: "daniel2@test.com",
        password: "password123",
        confirmPassword: "password1234",
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();
  const errorMessages = responseBody.errors.map((error: any) => error.message);
  expect(errorMessages).toContain("Passwords do not match.");
});

test("Incorrect createUserInput", async ({ request }) => {
  const query = {
    query: createUserQuery,
    variables: {
      createUserInput: {
        email: "daniel2@test.com",
        confirmPassword: "password123",
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
