import { test, expect } from "@playwright/test";

test("Introspection", async ({ request }) => {
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
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();
  expect(responseBody).toHaveProperty("data.__schema.types");
});
