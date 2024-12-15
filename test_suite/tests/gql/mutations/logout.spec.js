const { describe, test: base, expect } = require("@playwright/test");
const { DB } = require("../../../helpers");

const test = base.extend({
  db: async ({}, use) => {
    const database = new DB();
    await use(database);
  },
});

const logout_mutation = (refresh_token) => `
    mutation {
        logout(refreshToken: "${refresh_token}") {
            success
        }
    }`;

test.describe("After sign in", () => {
  test.beforeEach(async ({ db, request }, testInfo) => {
    const createUser = `
      mutation CreateUser($createUserInput: CreateUserInput) {
          createUser(input: $createUserInput) {
              accessToken
              refreshToken
          }
      }`;

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
    const responseBody = await response.json();
    testInfo.context = {};
    testInfo.context.refreshToken = responseBody.data.createUser.refreshToken;
  });

  test("Should log out user", async ({ request }, testInfo) => {
    const refreshToken = testInfo.context.refreshToken;
    const query = {
      query: logout_mutation(refreshToken),
      variables: {},
    };

    const response = await request.post("/graphql", {
      data: query,
    });

    expect(response.ok()).toBeTruthy();
    const responseBody = await response.json();
    expect(responseBody.data.logout.success).toBeDefined();
  });
});

test.afterEach(async ({ db }) => {
  await db.executeQuery("DELETE FROM users;");
});
