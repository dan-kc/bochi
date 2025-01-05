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

function expectGoodHabit(responseBody: any) {
  expect(responseBody.data.createHabit.id).toBeDefined();
  expect(responseBody.data.createHabit.name).toBeDefined();
  expect(responseBody.data.createHabit.difficulty).toBeDefined();
  expect(responseBody.data.createHabit.created_at).toBeDefined();
  expect(responseBody.data.createHabit.deleted_at).toBeDefined();
  expect(responseBody.data.createHabit.hidden_until).toBeDefined();
  expect(responseBody.data.createHabit.importance).toBeDefined();
  expect(responseBody.data.createHabit.duration).toBeDefined();
}
function expectError(responseBody: any, message: string) {
  const errorMessages = responseBody.errors.map((error: any) => error.message);
  expect(errorMessages).toContain(message);
}

const createHabitQuery = `
  mutation CreateHabit($createHabitInput: CreateHabitInput) {
    createHabit(input: $createHabitInput) {
      id
      name
      difficulty
      created_at
      deleted_at
      hidden_until
      importance
      duration
    }
  }
`;

test("Should create habit", async ({ request }) => {
  const query = {
    query: createHabitQuery,
    variables: {
      createHabitInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: 5,
        duration: 600,
        min_frequency: 365,
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
  expectGoodHabit(responseBody);
});

test("Should create habit with description", async ({ request }) => {
  const query = {
    query: createHabitQuery,
    variables: {
      createHabitInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: 5,
        duration: 600,
        description: "HI",
        min_frequency: 365,
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

  expectGoodHabit(responseBody);
  expect(responseBody.data.createHabit.description).toEqual("HI");
});

test("Should create hidden habit", async ({ request }) => {
  const query = {
    query: createHabitQuery,
    variables: {
      createHabitInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: 5,
        duration: 600,
        hidden_until: "2024-12-16T00:33:08+08:00",
        min_frequency: 365,
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
  expectGoodHabit(responseBody);
});

test("Should not create habit if name too long", async ({ request }) => {
  const query = {
    query: createHabitQuery,
    variables: {
      createHabitInput: {
        name: createStringOfLength(101),
        difficulty: 8,
        importance: 5,
        duration: 600,
        min_frequency: 365,
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

test("Should not create habit if difficulty > 10", async ({ request }) => {
  const query = {
    query: createHabitQuery,
    variables: {
      createHabitInput: {
        name: "Touch grass",
        difficulty: 11,
        importance: 5,
        duration: 600,
        min_frequency: 365,
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

  expectError(responseBody, "Difficulty can only be between 0 and 10");
});

test("Should not create habit if difficulty < 0", async ({ request }) => {
  const query = {
    query: createHabitQuery,
    variables: {
      createHabitInput: {
        name: "Touch grass",
        difficulty: -1,
        importance: 5,
        duration: 600,
        min_frequency: 365,
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

  expectError(responseBody, "Difficulty can only be between 0 and 10");
});

test("Should not create habit if importance < 0", async ({ request }) => {
  const query = {
    query: createHabitQuery,
    variables: {
      createHabitInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: -1,
        duration: 600,
        min_frequency: 365,
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

  expectError(responseBody, "Importance can only be between 0 and 10");
});

test("Should not create habit if importance > 10", async ({ request }) => {
  const query = {
    query: createHabitQuery,
    variables: {
      createHabitInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: 11,
        duration: 600,
        min_frequency: 365,
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

  expectError(responseBody, "Importance can only be between 0 and 10");
});

test("Should not create habit if duration < 0", async ({ request }) => {
  const query = {
    query: createHabitQuery,
    variables: {
      createHabitInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: 11,
        duration: -5,
        min_frequency: 365,
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

  expectError(responseBody, "Duration can't be negative");
});

test("Should not create task if duration longer than 24hrs", async ({
  request,
}) => {
  const query = {
    query: createHabitQuery,
    variables: {
      createHabitInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: 11,
        duration: 60 * 60 * 24 + 1,
        min_frequency: 365,
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

  expectError(responseBody, "Duration can't be more than 24hrs.");
});

test("Should not create habit with description if description too long.", async ({
  request,
}) => {
  const query = {
    query: createHabitQuery,
    variables: {
      createHabitInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: 8,
        duration: 5,
        description: createStringOfLength(10001),
        min_frequency: 365,
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

test("Should not create habit with min frequency too high.", async ({
  request,
}) => {
  const query = {
    query: createHabitQuery,
    variables: {
      createHabitInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: 11,
        duration: 5,
        min_frequency: 365001,
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
    "Minimum frequency too high. Must be less than 365001",
  );
});

test("Should not create habit with min frequency too low.", async ({
  request,
}) => {
  const query = {
    query: createHabitQuery,
    variables: {
      createHabitInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: 11,
        duration: 5,
        min_frequency: 0,
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
    "Minimum frequency too low. Must be greater than 0.",
  );
});

test("Should not create habit without valid access token", async ({
  request,
}) => {
  const query = {
    query: createHabitQuery,
    variables: {
      createHabitInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: 11,
        duration: 5,
        min_frequency: 365,
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

test("Should not create habit with expired access token", async ({
  request,
}) => {
  const query = {
    query: createHabitQuery,
    variables: {
      createHabitInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: 11,
        duration: 5,
        min_frequency: 365,
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
