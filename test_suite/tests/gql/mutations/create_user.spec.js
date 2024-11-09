const { test, expect } = require("@playwright/test");

test("Create valid user", async ({ request }) => {
  const query = {
    query: `
      mutation CreateUser($createUserInput: CreateUserInput) {
          createUser(input: $createUserInput) {
              id
          }
      }
    `,
    variables: {
      createUserInput: {
        userName: "daniel",
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
  expect(responseBody.data.createUser.id).toBeDefined();
});

test("Password too long", async ({ request }) => {
  const query = {
    query: `
      mutation CreateUser($createUserInput: CreateUserInput) {
          createUser(input: $createUserInput) {
              id
          }
      }
    `,
    variables: {
      createUserInput: {
        userName: "daniel",
        password: "01234567890123456789012345678901234567980123456789012345678901234",
        confirmPassword: "01234567890123456789012345678901234567980123456789012345678901234",
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();
  const errorMessages = responseBody.errors.map(error => error.message);
  expect(errorMessages).toContain("Password too long. The max password length is 64.")
});

test("Username too long", async ({ request }) => {
  const query = {
    query: `
      mutation CreateUser($createUserInput: CreateUserInput) {
          createUser(input: $createUserInput) {
              id
          }
      }
    `,
    variables: {
      createUserInput: {
        userName: "012345678901234567890",
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
  expect(errorMessages).toContain("Username too long. The max username length is 20.")
});

test("Password too short", async ({ request }) => {
  const query = {
    query: `
      mutation CreateUser($createUserInput: CreateUserInput) {
          createUser(input: $createUserInput) {
              id
          }
      }
    `,
    variables: {
      createUserInput: {
        userName: "daniel",
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
  expect(errorMessages).toContain("Password too short. The min password length is 6.");
});

test("Password mismatch", async ({ request }) => {
  const query = {
    query: `
      mutation CreateUser($createUserInput: CreateUserInput) {
          createUser(input: $createUserInput) {
              id
          }
      }
    `,
    variables: {
      createUserInput: {
        userName: "daniel",
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
  expect(errorMessages).toContain("Passwords do not match.")
});

test("Incorrect createUserInput", async ({ request }) => {
  const query = {
    query: `
      mutation CreateUser($createUserInput: CreateUserInput) {
          createUser(input: $createUserInput) {
              id
          }
      }
    `,
    variables: {
      createUserInput: {
        userName: "daniel",
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
  expect(errorMessages).toContain("Incorrect variables. Missing password.")
});
