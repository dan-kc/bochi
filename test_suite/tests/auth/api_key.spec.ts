import { expect } from "@playwright/test";
import { createAccessToken, test } from "../../helpers";

test.beforeEach(async ({ db }) => {
  await db.createUser();
});

test.afterEach(async ({ db }) => {
  await db.deleteAllUsers();
});

const createApiKeyQuery = `
  mutation CreateApiKey($createApiKeyInput: CreateApiKeyInput) {
    createApiKey(input: $createApiKeyInput) {
      name
      key
      createdAt
    }
  }
`;

test("Should return new api key", async ({ request }) => {
  const query = {
    query: createApiKeyQuery,
    variables: {
      createApiKeyInput: {
        name: "testname",
        password: "password123",
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
    headers: {
      Authorization: await createAccessToken(),
    },
  });

  const responseBody = await response.json();
  console.log(responseBody);

  expect(response.status()).toEqual(200);
  expect(responseBody.data.createApiKey.key).toBeDefined();
  expect(responseBody.data.createApiKey.createdAt).toBeDefined();
  expect(responseBody.data.createApiKey.name).toBeDefined();
});

test("Should not return api key if access token is expired", async ({
  request,
}) => {
  const query = {
    query: createApiKeyQuery,
    variables: {
      createApiKeyInput: {
        name: "testname",
        password: "password123",
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
    headers: {
      Authorization: await createAccessToken(true),
    },
  });

  expect(response.status()).toEqual(401);
});

test("Should not refresh token if no access token", async ({ request }) => {
  const query = {
    query: createApiKeyQuery,
    variables: {
      createApiKeyInput: {
        name: "testname",
        password: "password123",
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
  });

  expect(response.status()).toEqual(401);
});
