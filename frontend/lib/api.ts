import type { Task } from "./task";
import type { SyncPullResponse, SyncPushResponse } from "./sync/types";
import { getStoredTokens } from "./storage";

const API_PROTOCOL = process.env.EXPO_PUBLIC_API_PROTOCOL || "http";
const API_HOST = process.env.EXPO_PUBLIC_API_HOST || "localhost";
const API_PORT = process.env.EXPO_PUBLIC_API_PORT || "8501";
const API_BASE = `${API_PROTOCOL}://${API_HOST}:${API_PORT}`;
const GRAPHQL_ENDPOINT = `${API_BASE}/graphql`;

export interface AuthTokens {
  refreshToken: string;
  accessToken: string;
}

export type ValidationError =
  | "InvalidEmailAddress"
  | "EmailTooLong"
  | "PasswordNotAscii"
  | "PasswordTooLong"
  | "PasswordTooShort";

export interface ApiError {
  errors?: ValidationError[];
  message?: string;
  status?: number;
}

class ApiClient {
  private async request<T>(
    endpoint: string,
    options: RequestInit = {},
  ): Promise<T> {
    const response = await fetch(`${API_BASE}${endpoint}`, {
      ...options,
      headers: {
        "Content-Type": "application/json",
        ...options.headers,
      },
    });

    const data = await response.json();

    if (!response.ok) {
      throw { ...data, status: response.status } as ApiError;
    }

    return data as T;
  }

  async register(email: string, password: string): Promise<AuthTokens> {
    return this.request<AuthTokens>("/auth/register", {
      method: "POST",
      body: JSON.stringify({ email, password }),
    });
  }

  async login(email: string, password: string): Promise<AuthTokens> {
    return this.request<AuthTokens>("/auth/login", {
      method: "POST",
      body: JSON.stringify({ email, password }),
    });
  }

  async refreshTokens(refreshToken: string): Promise<AuthTokens> {
    return this.request<AuthTokens>("/auth/refresh-tokens", {
      method: "POST",
      body: JSON.stringify({ refreshToken }),
    });
  }

  async logout(refreshToken: string): Promise<{ success: boolean }> {
    return this.request<{ success: boolean }>("/auth/logout", {
      method: "POST",
      body: JSON.stringify({ refreshToken }),
    });
  }

  // ============ Authenticated requests ============

  private async authenticatedRequest<T>(
    endpoint: string,
    options: RequestInit = {},
  ): Promise<T> {
    const tokens = await getStoredTokens();
    if (!tokens) {
      throw { message: "Not authenticated" } as ApiError;
    }

    return this.request<T>(endpoint, {
      ...options,
      headers: {
        ...options.headers,
        Authorization: `Bearer ${tokens.accessToken}`,
      },
    });
  }

  // ============ GraphQL requests ============

  private async graphqlRequest<T>(
    query: string,
    variables?: Record<string, unknown>,
  ): Promise<T> {
    const tokens = await getStoredTokens();
    if (!tokens) {
      throw { message: "Not authenticated" } as ApiError;
    }

    const response = await fetch(GRAPHQL_ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${tokens.accessToken}`,
      },
      body: JSON.stringify({ query, variables }),
    });

    const json = await response.json();

    if (json.errors && json.errors.length > 0) {
      throw { message: json.errors[0].message } as ApiError;
    }

    return json.data as T;
  }

  // ============ Task sync endpoints (GraphQL) ============

  async pullTasks(since: string | null): Promise<SyncPullResponse> {
    const query = `
      query SyncPull($since: NaiveDateTime) {
        syncPull(since: $since) {
          tasks {
            id
            name
            description
            createdAt
            updatedAt
            deletedAt
            hiddenUntil
            dueBy
            minDailyFrequency
            difficultyRank
          }
          serverTime
        }
      }
    `;

    // Strip 'Z' suffix from since parameter (NaiveDateTime doesn't accept timezone)
    const sinceParsed = since ? since.replace(/Z$/, "") : null;

    const result = await this.graphqlRequest<{
      syncPull: {
        tasks: Array<{
          id: string;
          name: string;
          description: string;
          createdAt: string;
          updatedAt: string;
          deletedAt: string | null;
          hiddenUntil: string | null;
          dueBy: string | null;
          minDailyFrequency: number | null;
          difficultyRank: string | null;
        }>;
        serverTime: string;
      };
    }>(query, { since: sinceParsed });

    // Transform GraphQL response to match expected format
    return {
      tasks: result.syncPull.tasks.map((t) => ({
        id: t.id,
        user_id: "", // Not returned by GraphQL, populated locally
        name: t.name,
        description: t.description,
        created_at: t.createdAt,
        updated_at: t.updatedAt,
        deleted_at: t.deletedAt,
        hidden_until: t.hiddenUntil,
        due_by: t.dueBy,
        min_daily_frequency: t.minDailyFrequency,
        difficulty_rank: t.difficultyRank,
      })),
      server_time: result.syncPull.serverTime,
    };
  }

  async pushTasks(tasks: Task[]): Promise<SyncPushResponse> {
    const mutation = `
      mutation SyncPush($tasks: [SyncTaskInput!]!) {
        syncPush(tasks: $tasks) {
          tasks {
            id
            name
            description
            createdAt
            updatedAt
            deletedAt
            hiddenUntil
            dueBy
            minDailyFrequency
            difficultyRank
          }
          serverTime
        }
      }
    `;

    // Helper to strip 'Z' suffix from ISO dates (NaiveDateTime doesn't accept timezone)
    const toNaiveDateTime = (date: string | null): string | null =>
      date ? date.replace(/Z$/, "") : null;

    // Transform tasks to GraphQL input format (camelCase)
    const taskInputs = tasks.map((t) => ({
      id: t.id,
      name: t.name,
      description: t.description,
      createdAt: toNaiveDateTime(t.created_at),
      updatedAt: toNaiveDateTime(t.updated_at),
      deletedAt: toNaiveDateTime(t.deleted_at),
      hiddenUntil: toNaiveDateTime(t.hidden_until),
      dueBy: toNaiveDateTime(t.due_by),
      minDailyFrequency: t.min_daily_frequency,
      difficultyRank: t.difficulty_rank,
    }));

    const result = await this.graphqlRequest<{
      syncPush: {
        tasks: Array<{
          id: string;
          name: string;
          description: string;
          createdAt: string;
          updatedAt: string;
          deletedAt: string | null;
          hiddenUntil: string | null;
          dueBy: string | null;
          minDailyFrequency: number | null;
          difficultyRank: string | null;
        }>;
        serverTime: string;
      };
    }>(mutation, { tasks: taskInputs });

    // Transform GraphQL response to match expected format
    return {
      tasks: result.syncPush.tasks.map((t) => ({
        id: t.id,
        user_id: "", // Not returned by GraphQL, populated locally
        name: t.name,
        description: t.description,
        created_at: t.createdAt,
        updated_at: t.updatedAt,
        deleted_at: t.deletedAt,
        hidden_until: t.hiddenUntil,
        due_by: t.dueBy,
        min_daily_frequency: t.minDailyFrequency,
        difficulty_rank: t.difficultyRank,
      })),
      server_time: result.syncPush.serverTime,
    };
  }
}

export const api = new ApiClient();
