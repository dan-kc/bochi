const { test: base, expect } = require("@playwright/test");
const { DB } = require("../../../helpers");

const test = base.extend({
  db: async ({}, use) => {
    const database = new DB();
    await use(database);
  },
});
test.beforeEach(async ({ db }) => {
  await db.executeQuery(`
    WITH inserted_user AS (
      INSERT INTO users (email, password, salt) VALUES
      ('mock@email.com', '$argon2id$v=19$m=19456,t=2,p=1$M3qJL3+ctjCWEvCYFQuTGA$QUQcFKQxhQhIWP6DTBH3+iJtgmWBTMTe1DfcmljlSpw', 'M3qJL3+ctjCWEvCYFQuTGA')
      RETURNING id
    )
    INSERT INTO sessions (id, user_id) VALUES
    ('c11286fc_653d_4565_896f_21305fcbead7', (SELECT id FROM inserted_user));
  `);
});
test.afterEach(async ({ db }) => {
  await db.executeQuery("DELETE FROM users;");
});

const correct_login = `
      mutation {
          logout(id: "c11286fc_653d_4565_896f_21305fcbead7") {
              success
          }
      }`;

const incorrect_login = `
      mutation {
          logout(id: "d11286fc_653d_4565_d96f_21305fcbeadd") {
              success
          }
      }`;

test("Should log out user", async ({ request }) => {
  const query = {
    query: correct_login,
    variables: {},
  };

  const response = await request.post("/graphql", {
    data: query,
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();
  expect(responseBody.data.logout.success).toBeDefined();
});

test("Should return error for wrong session_id", async ({ request }) => {
  const query = {
    query: incorrect_login,
    variables: {},
  };

  const response = await request.post("/graphql", {
    data: query,
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();
  const errorMessages = responseBody.errors.map((error) => error.message);
  expect(errorMessages).toContain("Session does not exist. Already logged out.");
});
