import { expect } from "@playwright/test";
import { createAccessToken, test } from "../../helpers";

test.beforeEach(async ({ db }) => {
  await db.createUser();
});

test.afterEach(async ({ db }) => {
  await db.executeQuery("DELETE FROM users;");
});

test("Introspection", async ({ request, db }) => {
  const query = {
    query: `
      {
        __schema {
          types {
            name
          }
        }
      }
    `,
  };

  const response = await request.post("/graphql", {
    data: query,
    headers: {
      "Content-Type": "application/json",
      Authorization: await createAccessToken(),
    },
  });
  expect(response.status()).toEqual(200);
  const responseBody = await response.json();

  expect(responseBody).toHaveProperty("data.__schema.types");
});
