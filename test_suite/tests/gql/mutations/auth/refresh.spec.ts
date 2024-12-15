import { expect } from "@playwright/test";
import { test } from "../../../../helpers";

test.beforeEach(async ({ db }) => {
  await db.createUser();
});

test.afterEach(async ({ db }) => {
  await db.deleteAllUsers();
});

const createUserQuery = (refreshToken: string) => `
  mutation {
    refreshToken(input: ${refreshToken}) {
      refreshToken
      accessToken
    }
  }`;

test("Should refresh token", async ({ db, request }) => {
  const refreshToken = db.createRefreshToken();
  const query = {
    query: createUserQuery(refreshToken),
  };

  const response = await request.post("/graphql", {
    data: query,
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();
  expect(responseBody.data.createUser.refreshToken).toBeDefined();
  expect(responseBody.data.createUser.accessToken).toBeDefined();
});

test("Should not refresh token if expired", async ({ db, request }) => {
  const refreshToken = db.createRefreshToken(true);
  const query = {
    query: createUserQuery(refreshToken),
  };

  const response = await request.post("/graphql", {
    data: query,
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();
  const errorMessages = responseBody.errors.map((error: any) => error.message);
  expect(errorMessages).toContain("Invalid refresh token");
});

test("Should not refresh token if wrong uuid", async ({ db, request }) => {
  const query = {
    query: createUserQuery("b7eab812_9b9a_4823_930d_38c3c891ea8d"),
  };

  const response = await request.post("/graphql", {
    data: query,
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();
  const errorMessages = responseBody.errors.map((error: any) => error.message);
  expect(errorMessages).toContain("Invalid refresh token");
});
