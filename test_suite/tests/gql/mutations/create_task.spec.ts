import { expect } from "@playwright/test";
import { createAccessToken, createStringOfLength, test } from "../../../helpers";

test.beforeEach(async ({ db }) => {
  await db.createUser();
});

test.afterEach(async ({ db }) => {
  await db.deleteAllUsers();
});

function expectGoodTask(responseBody: any) {
  expect(responseBody.data.createTask.id).toBeDefined();
  expect(responseBody.data.createTask.name).toBeDefined();
  expect(responseBody.data.createTask.difficulty).toBeDefined();
  expect(responseBody.data.createTask.created_at).toBeDefined();
  expect(responseBody.data.createTask.deleted_at).toBeDefined();
  expect(responseBody.data.createTask.hidden_until).toBeDefined();
  expect(responseBody.data.createTask.due_at).toBeDefined();
  expect(responseBody.data.createTask.importance).toBeDefined();
  expect(responseBody.data.createTask.duration).toBeDefined();
}
function expectError(responseBody: any, message: string) {
  const errorMessages = responseBody.errors.map((error: any) => error.message);
  expect(errorMessages).toContain(message);
}

const createTaskQuery = `
  mutation CreateTask($createTaskInput: CreateTaskInput) {
    createTask(input: $createTaskInput) {
      id
      name
      difficulty
      created_at
      deleted_at
      hidden_until
      due_at
      importance
      duration
    }
  }
`;

test("Should create task", async ({ request }) => {
  const query = {
    query: createTaskQuery,
    variables: {
      createTaskInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: 5,
        duration: 600,
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
  expectGoodTask(responseBody);
});

test("Should create task with description", async ({ request }) => {
  const query = {
    query: createTaskQuery,
    variables: {
      createTaskInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: 5,
        duration: 600,
        description: "HI",
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

  expectGoodTask(responseBody);
  expect(responseBody.data.createTask.description).toEqual("HI");
});

test("Should create hidden task", async ({ request }) => {
  const query = {
    query: createTaskQuery,
    variables: {
      createTaskInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: 5,
        duration: 600,
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
  expectGoodTask(responseBody);
});

test("Should create due task", async ({ request }) => {
  const query = {
    query: createTaskQuery,
    variables: {
      createTaskInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: 5,
        duration: 600,
        due_date: "2024-12-16T00:33:08+08:00",
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
  expectGoodTask(responseBody);
});

test("Should not create task if name too long", async ({ request }) => {
  const query = {
    query: createTaskQuery,
    variables: {
      createTaskInput: {
        name: createStringOfLength(101),
        difficulty: 8,
        importance: 5,
        duration: 600,
        due_date: "2024-12-16T00:33:08+08:00",
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

test("Should not create task if difficulty > 10", async ({ request }) => {
  const query = {
    query: createTaskQuery,
    variables: {
      createTaskInput: {
        name: "Touch grass",
        difficulty: 11,
        importance: 5,
        duration: 600,
        due_date: "2024-12-16T00:33:08+08:00",
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

test("Should not create task if difficulty < 0", async ({ request }) => {
  const query = {
    query: createTaskQuery,
    variables: {
      createTaskInput: {
        name: "Touch grass",
        difficulty: -1,
        importance: 5,
        duration: 600,
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

test("Should not create task if importance < 0", async ({ request }) => {
  const query = {
    query: createTaskQuery,
    variables: {
      createTaskInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: -1,
        duration: 600,
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

test("Should not create task if importance > 10", async ({ request }) => {
  const query = {
    query: createTaskQuery,
    variables: {
      createTaskInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: 11,
        duration: 600,
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

test("Should not create task if duration < 0", async ({ request }) => {
  const query = {
    query: createTaskQuery,
    variables: {
      createTaskInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: 11,
        duration: -5,
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

test("Should not create task with description if description too long.", async ({
  request,
}) => {
  const query = {
    query: createTaskQuery,
    variables: {
      createTaskInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: 11,
        duration: 5,
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

test("Should not create task without valid access token", async ({
  request,
}) => {
  const query = {
    query: createTaskQuery,
    variables: {
      createTaskInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: 11,
        duration: 5,
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

test("Should not create task with expired access token", async ({
  request,
}) => {
  const query = {
    query: createTaskQuery,
    variables: {
      createTaskInput: {
        name: "Touch grass",
        difficulty: 8,
        importance: 11,
        duration: 5,
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
