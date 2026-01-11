import { Platform } from "react-native";
import type { Task } from "./task";
import type { Trade } from "./trade";
import type {
  SyncPullResponse,
  SyncPushResponse,
  SyncPullTradesResponse,
  SyncPushTradesResponse,
  BalanceResponse,
} from "./sync/types";
import { getStoredTokens } from "./storage";

const API_PROTOCOL = process.env.EXPO_PUBLIC_API_PROTOCOL || "http";
const API_HOST = process.env.EXPO_PUBLIC_API_HOST || "localhost";
const API_PORT = process.env.EXPO_PUBLIC_API_PORT || "8501";
const API_BASE = `${API_PROTOCOL}://${API_HOST}:${API_PORT}`;
const GRAPHQL_ENDPOINT = `${API_BASE}/graphql`;

// On web, we use cookies for auth (sent automatically with credentials: 'include')
// On native, we use Authorization header with tokens from SecureStore
const isWeb = Platform.OS === "web";

export interface AuthTokens {
  refreshToken: string;
  accessToken: string;
}

export interface ApiErrorItem {
  code: string;
  message: string;
}

export interface ApiError {
  errors?: ApiErrorItem[];
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
      // Include credentials so cookies are sent/received on web
      credentials: isWeb ? "include" : "omit",
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

  async refreshTokens(refreshToken?: string): Promise<AuthTokens> {
    // On web, cookie is sent automatically - no need for body
    // On native, send refresh token in body
    const body = isWeb ? {} : { refreshToken };
    return this.request<AuthTokens>("/auth/refresh-tokens", {
      method: "POST",
      body: JSON.stringify(body),
    });
  }

  async logout(refreshToken?: string): Promise<{ success: boolean }> {
    // On web, cookie is sent automatically - no need for body
    // On native, send refresh token in body
    const body = isWeb ? {} : { refreshToken };
    return this.request<{ success: boolean }>("/auth/logout", {
      method: "POST",
      body: JSON.stringify(body),
    });
  }

  async anonymousAuth(deviceId: string): Promise<AuthTokens> {
    return this.request<AuthTokens>("/auth/anonymous", {
      method: "POST",
      body: JSON.stringify({ deviceId }),
    });
  }

  async claimAccount(
    email: string,
    password: string,
    accessToken?: string,
  ): Promise<AuthTokens> {
    // On web, cookie is sent automatically
    // On native, we need to send the access token
    const headers: Record<string, string> = {};
    if (!isWeb && accessToken) {
      headers["Authorization"] = `Bearer ${accessToken}`;
    }

    return this.request<AuthTokens>("/auth/claim", {
      method: "POST",
      body: JSON.stringify({ email, password }),
      headers,
    });
  }

  // ============ Authenticated requests ============

  private async authenticatedRequest<T>(
    endpoint: string,
    options: RequestInit = {},
  ): Promise<T> {
    // On web, cookies are sent automatically with credentials: 'include'
    // On native, we need to get tokens from SecureStore and send Authorization header
    if (isWeb) {
      return this.request<T>(endpoint, options);
    }

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
    // On web, cookies are sent automatically with credentials: 'include'
    // On native, we need to get tokens from SecureStore and send Authorization header
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
    };

    if (!isWeb) {
      const tokens = await getStoredTokens();
      if (!tokens) {
        throw { message: "Not authenticated" } as ApiError;
      }
      headers["Authorization"] = `Bearer ${tokens.accessToken}`;
    }

    const response = await fetch(GRAPHQL_ENDPOINT, {
      method: "POST",
      credentials: isWeb ? "include" : "omit",
      headers,
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
            completedAt
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
          completedAt: string | null;
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
        completed_at: t.completedAt,
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
            completedAt
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
      completedAt: toNaiveDateTime(t.completed_at),
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
          completedAt: string | null;
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
        completed_at: t.completedAt,
      })),
      server_time: result.syncPush.serverTime,
    };
  }

  // ============ Trade sync endpoints (GraphQL) ============

  async pullTrades(since: string | null): Promise<SyncPullTradesResponse> {
    const query = `
      query SyncPullTrades($since: NaiveDateTime) {
        syncPullTrades(since: $since) {
          trades {
            id
            taskId
            rewardId
            amount
            createdAt
            updatedAt
            deletedAt
          }
          serverTime
        }
      }
    `;

    const sinceParsed = since ? since.replace(/Z$/, "") : null;

    const result = await this.graphqlRequest<{
      syncPullTrades: {
        trades: Array<{
          id: string;
          taskId: string | null;
          rewardId: string | null;
          amount: number;
          createdAt: string;
          updatedAt: string;
          deletedAt: string | null;
        }>;
        serverTime: string;
      };
    }>(query, { since: sinceParsed });

    return {
      trades: result.syncPullTrades.trades.map((t) => ({
        id: t.id,
        user_id: "", // Populated locally
        task_id: t.taskId,
        reward_id: t.rewardId,
        amount: t.amount,
        created_at: t.createdAt,
        updated_at: t.updatedAt,
        deleted_at: t.deletedAt,
      })),
      server_time: result.syncPullTrades.serverTime,
    };
  }

  async pushTrades(trades: Trade[]): Promise<SyncPushTradesResponse> {
    const mutation = `
      mutation SyncPushTrades($trades: [SyncTradeInput!]!) {
        syncPushTrades(trades: $trades) {
          trades {
            id
            taskId
            rewardId
            amount
            createdAt
            updatedAt
            deletedAt
          }
          serverTime
          newBalance
        }
      }
    `;

    const toNaiveDateTime = (date: string | null): string | null =>
      date ? date.replace(/Z$/, "") : null;

    const tradeInputs = trades.map((t) => ({
      id: t.id,
      taskId: t.task_id,
      rewardId: t.reward_id,
      amount: t.amount,
      createdAt: toNaiveDateTime(t.created_at),
      deletedAt: toNaiveDateTime(t.deleted_at),
    }));

    const result = await this.graphqlRequest<{
      syncPushTrades: {
        trades: Array<{
          id: string;
          taskId: string | null;
          rewardId: string | null;
          amount: number;
          createdAt: string;
          updatedAt: string;
          deletedAt: string | null;
        }>;
        serverTime: string;
        newBalance: number;
      };
    }>(mutation, { trades: tradeInputs });

    return {
      trades: result.syncPushTrades.trades.map((t) => ({
        id: t.id,
        user_id: "", // Populated locally
        task_id: t.taskId,
        reward_id: t.rewardId,
        amount: t.amount,
        created_at: t.createdAt,
        updated_at: t.updatedAt,
        deleted_at: t.deletedAt,
      })),
      server_time: result.syncPushTrades.serverTime,
      new_balance: result.syncPushTrades.newBalance,
    };
  }

  async getBalance(): Promise<BalanceResponse> {
    const query = `
      query Balance {
        balance {
          soyBalance
          tofuBalance
        }
      }
    `;

    const result = await this.graphqlRequest<{
      balance: {
        soyBalance: number;
        tofuBalance: number;
      };
    }>(query);

    return {
      soy_balance: result.balance.soyBalance,
      tofu_balance: result.balance.tofuBalance,
    };
  }
}

export const api = new ApiClient();
