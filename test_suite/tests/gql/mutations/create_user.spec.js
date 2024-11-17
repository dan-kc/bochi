const { test, expect } = require("@playwright/test");

const createUser = `
      mutation CreateUser($createUserInput: CreateUserInput) {
          createUser(input: $createUserInput) {
              user {
                  id
                  email
              }
              sessionId
          }
      }`;

test("Create valid user", async ({ request }) => {
  const query = {
    query: createUser,
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
  expect(responseBody.data.createUser.sessionId).toBeDefined();
  expect(responseBody.data.createUser.user.id).toBeDefined();
  expect(responseBody.data.createUser.user.email).toBeDefined();
});

test("Password too long", async ({ request }) => {
  const query = {
    query: createUser,
    variables: {
      createUserInput: {
        email: "daniel2@test.com",
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
  const errorMessages = responseBody.errors.map((error) => error.message);
  expect(errorMessages).toContain(
    "Password too long. The max password length is 64.",
  );
});

test("Password not ascii", async ({ request }) => {
  const query = {
    query: createUser,
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
  const errorMessages = responseBody.errors.map((error) => error.message);
  expect(errorMessages).toContain(
    "Password must contain only standard English letters, numbers, and common punctuation.",
  );
});

test("invalid email", async ({ request }) => {
  const query = {
    query: createUser,
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
  const errorMessages = responseBody.errors.map((error) => error.message);
  expect(errorMessages).toContain("Invalid email address.");
});

test("email too long", async ({ request }) => {
  const query = {
    query: createUser,
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
  const errorMessages = responseBody.errors.map((error) => error.message);
  expect(errorMessages).toContain(
    "Email too long. The max email length is 40.",
  );
});

test("Password too short", async ({ request }) => {
  const query = {
    query: createUser,
    variables: {
      createUserInput: {
        email: "daniel2@test.com",
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
  const errorMessages = responseBody.errors.map((error) => error.message);
  expect(errorMessages).toContain(
    "Password too short. The min password length is 8.",
  );
});

test("Password mismatch", async ({ request }) => {
  const query = {
    query: createUser,
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
  const errorMessages = responseBody.errors.map((error) => error.message);
  expect(errorMessages).toContain("Passwords do not match.");
});

test("Incorrect createUserInput", async ({ request }) => {
  const query = {
    query: createUser,
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
  const errorMessages = responseBody.errors.map((error) => error.message);
  expect(errorMessages).toContain("Invalid value for argument \"input\", field \"password\" of type \"String!\" is required but not provided");
});
