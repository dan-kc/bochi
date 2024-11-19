const { test: base, expect } = require("@playwright/test");
const { DB } = require('../../../helpers');

const test = base.extend({
  db: async ({}, use) => {
    const database = new DB();
    await use(database);
  },
});
test.beforeEach(async ({ db }) => {
  await db.executeQuery(`
    INSERT INTO users (email, password, salt) VALUES
    ('mock@email.com', '$argon2id$v=19$m=19456,t=2,p=1$M3qJL3+ctjCWEvCYFQuTGA$QUQcFKQxhQhIWP6DTBH3+iJtgmWBTMTe1DfcmljlSpw', 'M3qJL3+ctjCWEvCYFQuTGA');
  `);
});
test.afterEach(async ({ db }) => {
  await db.executeQuery("DELETE FROM users;");
});

const login = `
      mutation login($loginInput: LoginInput) {
          login(input: $loginInput) {
              user {
                  id
                  email
              }
              sessionId
          }
      }`;

test("Should log in user", async ({ request }) => {
  const query = {
    query: login,
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
  expect(responseBody.data.login.sessionId).toBeDefined();
  expect(responseBody.data.login.user.id).toBeDefined();
  expect(responseBody.data.login.user.email).toBeDefined();
});

test("Should return error for incorrect email", async ({ request }) => {
  const query = {
    query: login,
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
  const errorMessages = responseBody.errors.map((error) => error.message);
  expect(errorMessages).toContain("Incorrect email or password.");
});

test("Should return error for incorrect password", async ({ request }) => {
  const query = {
    query: login,
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
  const errorMessages = responseBody.errors.map((error) => error.message);
  expect(errorMessages).toContain("Incorrect email or password.");
});


test("Should return error for missing password field", async ({ request }) => {
  const query = {
    query: login,
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
  const errorMessages = responseBody.errors.map((error) => error.message);
  expect(errorMessages).toContain("Invalid value for argument \"input\", field \"password\" of type \"String!\" is required but not provided");
});
