import { expect } from "@playwright/test";
import { test } from "../../../../helpers";

test.beforeEach(async ({ db }) => {
  await db.createUser();
});

test.afterEach(async ({ db }) => {
  await db.executeQuery("DELETE FROM users;");
});

const logout_mutation = (refresh_token: String) => `
    mutation {
        logout(refreshToken: "${refresh_token}") {
            success
        }
    }`;

test("Should log out user", async ({ db, request }) => {
  const refreshToken = await db.createRefreshToken();
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

test("Should log out user with expired token", async ({ db, request }) => {
  const refreshToken = await db.createRefreshToken(true);
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
