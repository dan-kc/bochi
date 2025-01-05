import { expect } from "@playwright/test";
import {
  createAccessToken,
  createStringOfLength,
  test,
} from "../../../helpers";

test.beforeEach(async ({ db }) => {
  await db.createUser();
});

test.afterEach(async ({ db }) => {
  await db.deleteAllUsers();
});

function expectGoodTreat(responseBody: any) {
  expect(responseBody.data.createTreat.id).toBeDefined();
  expect(responseBody.data.createTreat.name).toBeDefined();
  expect(responseBody.data.createTreat.created_at).toBeDefined();
  expect(responseBody.data.createTreat.deleted_at).toBeDefined();
  expect(responseBody.data.createTreat.hidden_until).toBeDefined();
  expect(responseBody.data.createTreat.description).toBeDefined();
  expect(responseBody.data.createTreat.damage).toBeDefined();
  expect(responseBody.data.createTreat.pleasure).toBeDefined();
}
function expectError(responseBody: any, message: string) {
  const errorMessages = responseBody.errors.map((error: any) => error.message);
  expect(errorMessages).toContain(message);
}

const createTreatQuery = `
  mutation CreateTreat($createTreatInput: CreateTreatInput) {
    createTreat(input: $createTreatInput) {
      id
      name
      created_at
      deleted_at
      hidden_until
      description
      damage
      pleasure
    }
  }
`;

test("Should create treat", async ({ request }) => {
  const query = {
    query: createTreatQuery,
    variables: {
      createTreatInput: {
        name: "Drink a cup of coffee",
        damage: 6,
        pleasure: 7,
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
    headers: {
      Authorization: await createAccessToken(),
    },
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();
  expectGoodTreat(responseBody);
});

test("Should create treat with description", async ({ request }) => {
  const query = {
    query: createTreatQuery,
    variables: {
      createTreatInput: {
        name: "Drink Coffee",
        damage: 6,
        pleasure: 7,
        description: "Drink 1 regular size cup of coffee",
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
    headers: {
      Authorization: await createAccessToken(),
    },
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();

  expectGoodTreat(responseBody);
  expect(responseBody.data.createTreat.description).toEqual("HI");
});

test("Should not create treat with description if description too long.", async ({
  request,
}) => {
  const query = {
    query: createTreatQuery,
    variables: {
      createTreatInput: {
        name: "Drink Coffee",
        damage: 6,
        pleasure: 7,
        description: createStringOfLength(10001),
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
    headers: {
      Authorization: await createAccessToken(),
    },
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();

  expectError(
    responseBody,
    "Description too long. Must be fewer that 10000 chars.",
  );
});

test("Should create hidden treat", async ({ request }) => {
  const query = {
    query: createTreatQuery,
    variables: {
      createTreatInput: {
        name: "Drink Coffee",
        damage: 6,
        pleasure: 7,
        hidden_until: "2024-12-16T00:33:08+08:00",
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
    headers: {
      Authorization: await createAccessToken(),
    },
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();
  expectGoodTreat(responseBody);
});

test("Should not create treat if name too long", async ({ request }) => {
  const query = {
    query: createTreatQuery,
    variables: {
      createTreatInput: {
        name: createStringOfLength(101),
        damage: 6,
        pleasure: 7,
        importance: 5,
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
    headers: {
      Authorization: await createAccessToken(),
    },
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();

  expectError(responseBody, "Name is too long. Must be fewer than 100 chars.");
});

test("Should not create treat if damage < 0", async ({ request }) => {
  const query = {
    query: createTreatQuery,
    variables: {
      createTreatInput: {
        name: "Drink Coffee",
        damage: -1,
        pleasure: 7,
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
    headers: {
      Authorization: await createAccessToken(),
    },
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();

  expectError(responseBody, "damage can only be between 0 and 10");
});

test("Should not create treat if damage > 10", async ({ request }) => {
  const query = {
    query: createTreatQuery,
    variables: {
      createTreatInput: {
        name: "Drink Coffee",
        damage: 11,
        pleasure: 7,
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
    headers: {
      Authorization: await createAccessToken(),
    },
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();

  expectError(responseBody, "damage can only be between 0 and 10");
});

test("Should not create treat if pleasure < 0", async ({ request }) => {
  const query = {
    query: createTreatQuery,
    variables: {
      createTreatInput: {
        name: "Drink Coffee",
        damage: 11,
        pleasure: -1,
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
    headers: {
      Authorization: await createAccessToken(),
    },
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();

  expectError(responseBody, "pleasure can only be between 0 and 10");
});

test("Should not create treat if pleasure > 10", async ({ request }) => {
  const query = {
    query: createTreatQuery,
    variables: {
      createTreatInput: {
        name: "Drink Coffee",
        damage: 11,
        pleasure: 11,
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
    headers: {
      Authorization: await createAccessToken(),
    },
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();

  expectError(responseBody, "pleasure can only be between 0 and 10");
});


test("Should not create treat without valid access token", async ({
  request,
}) => {
  const query = {
    query: createTreatQuery,
    variables: {
      createTreatInput: {
        name: "Launch Habit Market",
        importance: 5,
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();

  expectError(responseBody, "Invalid access token");
});

test("Should not create treat with expired access token", async ({
  request,
}) => {
  const query = {
    query: createTreatQuery,
    variables: {
      createTreatInput: {
        name: "Launch Habit Market",
        importance: 5,
      },
    },
  };

  const response = await request.post("/graphql", {
    data: query,
    headers: {
      Authorization: await createAccessToken(true),
    },
  });

  expect(response.ok()).toBeTruthy();
  const responseBody = await response.json();

  expectError(responseBody, "Invalid access token");
});
