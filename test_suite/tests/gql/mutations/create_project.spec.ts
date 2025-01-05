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

function expectGoodProject(responseBody: any) {
  expect(responseBody.data.createProject.id).toBeDefined();
  expect(responseBody.data.createProject.name).toBeDefined();
  expect(responseBody.data.createProject.created_at).toBeDefined();
  expect(responseBody.data.createProject.deleted_at).toBeDefined();
  expect(responseBody.data.createProject.hidden_until).toBeDefined();
  expect(responseBody.data.createProject.due_by).toBeDefined();
  expect(responseBody.data.createProject.importance).toBeDefined();
}
function expectError(responseBody: any, message: string) {
  const errorMessages = responseBody.errors.map((error: any) => error.message);
  expect(errorMessages).toContain(message);
}

const createProjectQuery = `
  mutation CreateProject($createProjectInput: CreateProjectInput) {
    createProject(input: $createProjectInput) {
      id
      name
      created_at
      deleted_at
      hidden_until
      due_by
      description
      importance
    }
  }
`;

test("Should create project", async ({ request }) => {
  const query = {
    query: createProjectQuery,
    variables: {
      createProjectInput: {
        name: "Launch Habit Market",
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
  expectGoodProject(responseBody);
});

test("Should create project with description", async ({ request }) => {
  const query = {
    query: createProjectQuery,
    variables: {
      createProjectInput: {
        name: "Launch Habit Market",
        importance: 5,
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

  expectGoodProject(responseBody);
  expect(responseBody.data.createProject.description).toEqual("HI");
});

test("Should create hidden project", async ({ request }) => {
  const query = {
    query: createProjectQuery,
    variables: {
      createProjectInput: {
        name: "Launch Habit Market",
        importance: 5,
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
  expectGoodProject(responseBody);
});

test("Should create project with due_by", async ({ request }) => {
  const query = {
    query: createProjectQuery,
    variables: {
      createProjectInput: {
        name: "Launch Habit Market",
        importance: 5,
        due_by: "2024-12-16T00:33:08+08:00",
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
  expectGoodProject(responseBody);
});

test("Should not create project if name too long", async ({ request }) => {
  const query = {
    query: createProjectQuery,
    variables: {
      createProjectInput: {
        name: createStringOfLength(101),
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

test("Should not create project if importance < 0", async ({ request }) => {
  const query = {
    query: createProjectQuery,
    variables: {
      createProjectInput: {
        name: "Launch Habit Market",
        importance: -1,
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

test("Should not create project if importance > 10", async ({ request }) => {
  const query = {
    query: createProjectQuery,
    variables: {
      createProjectInput: {
        name: "Launch Habit Market",
        importance: 11,
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

test("Should not create project without valid access token", async ({
  request,
}) => {
  const query = {
    query: createProjectQuery,
    variables: {
      createProjectInput: {
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

test("Should not create project with expired access token", async ({
  request,
}) => {
  const query = {
    query: createProjectQuery,
    variables: {
      createProjectInput: {
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
