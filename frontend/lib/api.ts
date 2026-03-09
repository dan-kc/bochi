import { Platform } from "react-native";
import type {
  BalanceResponse,
  SyncResponse,
  SyncInput,
} from "./sync/types";
import { getStoredTokens } from "./storage";

const API_PROTOCOL = process.env.EXPO_PUBLIC_API_PROTOCOL || "http";
const API_HOST = process.env.EXPO_PUBLIC_API_HOST || "localhost";
const API_PORT = process.env.EXPO_PUBLIC_API_PORT || "8501";
const API_BASE = `${API_PROTOCOL}://${API_HOST}:${API_PORT}`;

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

  async changePassword(
    currentPassword: string,
    newPassword: string,
    accessToken?: string,
  ): Promise<{ success: boolean }> {
    // On web, cookie is sent automatically
    // On native, we need to send the access token
    const headers: Record<string, string> = {};
    if (!isWeb && accessToken) {
      headers["Authorization"] = `Bearer ${accessToken}`;
    }

    return this.request<{ success: boolean }>("/auth/change-password", {
      method: "POST",
      body: JSON.stringify({ currentPassword, newPassword }),
      headers,
    });
  }

  async changeEmail(
    newEmail: string,
    password: string,
    accessToken?: string,
  ): Promise<{ success: boolean }> {
    // On web, cookie is sent automatically
    // On native, we need to send the access token
    const headers: Record<string, string> = {};
    if (!isWeb && accessToken) {
      headers["Authorization"] = `Bearer ${accessToken}`;
    }

    return this.request<{ success: boolean }>("/auth/change-email", {
      method: "POST",
      body: JSON.stringify({ newEmail, password }),
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

  // ============ REST API endpoints ============

  async getBalance(): Promise<BalanceResponse> {
    const result = await this.authenticatedRequest<{
      tofuBalance: number;
    }>("/api/balance", { method: "GET" });

    return {
      tofu_balance: result.tofuBalance,
    };
  }

  async sync(since: string | null): Promise<SyncResponse> {
    // Strip 'Z' suffix from since parameter (NaiveDateTime doesn't accept timezone)
    const sinceParsed = since ? since.replace(/Z$/, "") : null;
    const url = sinceParsed
      ? `/api/sync?since=${encodeURIComponent(sinceParsed)}`
      : "/api/sync";

    const result = await this.authenticatedRequest<{
      habits: Array<{
        id: string;
        name: string;
        description: string;
        createdAt: string;
        updatedAt: string;
        deletedAt: string | null;

        minDailyFrequency: number | null;
        difficultyRank: string | null;
      }>;
      trades: Array<{
        id: string;
        habitId: string | null;
        rewardId: string | null;
        amount: number;
        createdAt: string;
        updatedAt: string;
        deletedAt: string | null;
      }>;
      tags: Array<{
        id: string;
        name: string;
        colorHex: string;
        createdAt: string;
        updatedAt: string;
        deletedAt: string | null;
      }>;
      habitTags: Array<{
        habitId: string;
        tagId: string;
        createdAt: string;
        updatedAt: string;
        deletedAt: string | null;
      }>;
      rewards: Array<{
        id: string;
        name: string;
        description: string;
        createdAt: string;
        updatedAt: string;
        deletedAt: string | null;

        maxDailyFrequency: number | null;
        damageRank: string | null;
      }>;
      rewardTags: Array<{
        rewardId: string;
        tagId: string;
        createdAt: string;
        updatedAt: string;
        deletedAt: string | null;
      }>;
      balance: {
        tofuBalance: number;
      };
      serverTime: string;
      email: string | null;
      isPremium: boolean;
    }>(url, { method: "GET" });

    return {
      habits: result.habits.map((h) => ({
        id: h.id,
        user_id: "",
        name: h.name,
        description: h.description,
        created_at: h.createdAt,
        updated_at: h.updatedAt,
        deleted_at: h.deletedAt,

        min_daily_frequency: h.minDailyFrequency,
        difficulty_rank: h.difficultyRank,
      })),
      trades: result.trades.map((t) => ({
        id: t.id,
        user_id: "",
        habit_id: t.habitId,
        reward_id: t.rewardId,
        amount: t.amount,
        created_at: t.createdAt,
        updated_at: t.updatedAt,
        deleted_at: t.deletedAt,
      })),
      tags: result.tags.map((t) => ({
        id: t.id,
        user_id: "",
        name: t.name,
        color_hex: t.colorHex,
        created_at: t.createdAt,
        updated_at: t.updatedAt,
        deleted_at: t.deletedAt,
      })),
      habitTags: result.habitTags.map((ht) => ({
        habit_id: ht.habitId,
        tag_id: ht.tagId,
        user_id: "",
        created_at: ht.createdAt,
        updated_at: ht.updatedAt,
        deleted_at: ht.deletedAt,
      })),
      rewards: result.rewards.map((r) => ({
        id: r.id,
        user_id: "",
        name: r.name,
        description: r.description,
        created_at: r.createdAt,
        updated_at: r.updatedAt,
        deleted_at: r.deletedAt,

        max_daily_frequency: r.maxDailyFrequency,
        damage_rank: r.damageRank,
      })),
      rewardTags: result.rewardTags.map((rt) => ({
        reward_id: rt.rewardId,
        tag_id: rt.tagId,
        user_id: "",
        created_at: rt.createdAt,
        updated_at: rt.updatedAt,
        deleted_at: rt.deletedAt,
      })),
      balance: {
        tofu_balance: result.balance.tofuBalance,
      },
      server_time: result.serverTime,
      email: result.email,
      isPremium: result.isPremium,
    };
  }

  async syncPush(input: SyncInput): Promise<SyncResponse> {
    const toNaiveDateTime = (date: string | null): string | null =>
      date ? date.replace(/Z$/, "") : null;

    // Transform habits to REST input format (camelCase)
    const habitInputs = input.habits?.map((h) => ({
      id: h.id,
      name: h.name,
      description: h.description,
      createdAt: toNaiveDateTime(h.createdAt) ?? "",
      updatedAt: toNaiveDateTime(h.updatedAt) ?? "",
      deletedAt: toNaiveDateTime(h.deletedAt),

      minDailyFrequency: h.minDailyFrequency,
      difficultyRank: h.difficultyRank,
    }));

    // Transform trades to REST input format (camelCase)
    const tradeInputs = input.trades?.map((t) => ({
      id: t.id,
      habitId: t.habitId,
      rewardId: t.rewardId,
      amount: t.amount,
      createdAt: toNaiveDateTime(t.createdAt) ?? "",
      deletedAt: toNaiveDateTime(t.deletedAt),
    }));

    // Transform tags to REST input format (camelCase)
    const tagInputs = input.tags?.map((t) => ({
      id: t.id,
      name: t.name,
      colorHex: t.colorHex,
      createdAt: toNaiveDateTime(t.createdAt) ?? "",
      updatedAt: toNaiveDateTime(t.updatedAt) ?? "",
      deletedAt: toNaiveDateTime(t.deletedAt),
    }));

    // Transform habitTags to REST input format (camelCase)
    const habitTagInputs = input.habitTags?.map((ht) => ({
      habitId: ht.habitId,
      tagId: ht.tagId,
      createdAt: toNaiveDateTime(ht.createdAt) ?? "",
      updatedAt: toNaiveDateTime(ht.updatedAt) ?? "",
      deletedAt: toNaiveDateTime(ht.deletedAt),
    }));

    // Transform rewards to REST input format (camelCase)
    const rewardInputs = input.rewards?.map((r) => ({
      id: r.id,
      name: r.name,
      description: r.description,
      createdAt: toNaiveDateTime(r.createdAt) ?? "",
      updatedAt: toNaiveDateTime(r.updatedAt) ?? "",
      deletedAt: toNaiveDateTime(r.deletedAt),

      maxDailyFrequency: r.maxDailyFrequency,
      damageRank: r.damageRank,
    }));

    // Transform rewardTags to REST input format (camelCase)
    const rewardTagInputs = input.rewardTags?.map((rt) => ({
      rewardId: rt.rewardId,
      tagId: rt.tagId,
      createdAt: toNaiveDateTime(rt.createdAt) ?? "",
      updatedAt: toNaiveDateTime(rt.updatedAt) ?? "",
      deletedAt: toNaiveDateTime(rt.deletedAt),
    }));

    const result = await this.authenticatedRequest<{
      habits: Array<{
        id: string;
        name: string;
        description: string;
        createdAt: string;
        updatedAt: string;
        deletedAt: string | null;

        minDailyFrequency: number | null;
        difficultyRank: string | null;
      }>;
      trades: Array<{
        id: string;
        habitId: string | null;
        rewardId: string | null;
        amount: number;
        createdAt: string;
        updatedAt: string;
        deletedAt: string | null;
      }>;
      tags: Array<{
        id: string;
        name: string;
        colorHex: string;
        createdAt: string;
        updatedAt: string;
        deletedAt: string | null;
      }>;
      habitTags: Array<{
        habitId: string;
        tagId: string;
        createdAt: string;
        updatedAt: string;
        deletedAt: string | null;
      }>;
      rewards: Array<{
        id: string;
        name: string;
        description: string;
        createdAt: string;
        updatedAt: string;
        deletedAt: string | null;

        maxDailyFrequency: number | null;
        damageRank: string | null;
      }>;
      rewardTags: Array<{
        rewardId: string;
        tagId: string;
        createdAt: string;
        updatedAt: string;
        deletedAt: string | null;
      }>;
      balance: {
        tofuBalance: number;
      };
      serverTime: string;
      email: string | null;
      isPremium: boolean;
    }>("/api/sync", {
      method: "POST",
      body: JSON.stringify({
        habits: habitInputs,
        trades: tradeInputs,
        tags: tagInputs,
        habitTags: habitTagInputs,
        rewards: rewardInputs,
        rewardTags: rewardTagInputs,
      }),
    });

    return {
      habits: result.habits.map((h) => ({
        id: h.id,
        user_id: "",
        name: h.name,
        description: h.description,
        created_at: h.createdAt,
        updated_at: h.updatedAt,
        deleted_at: h.deletedAt,

        min_daily_frequency: h.minDailyFrequency,
        difficulty_rank: h.difficultyRank,
      })),
      trades: result.trades.map((t) => ({
        id: t.id,
        user_id: "",
        habit_id: t.habitId,
        reward_id: t.rewardId,
        amount: t.amount,
        created_at: t.createdAt,
        updated_at: t.updatedAt,
        deleted_at: t.deletedAt,
      })),
      tags: result.tags.map((t) => ({
        id: t.id,
        user_id: "",
        name: t.name,
        color_hex: t.colorHex,
        created_at: t.createdAt,
        updated_at: t.updatedAt,
        deleted_at: t.deletedAt,
      })),
      habitTags: result.habitTags.map((ht) => ({
        habit_id: ht.habitId,
        tag_id: ht.tagId,
        user_id: "",
        created_at: ht.createdAt,
        updated_at: ht.updatedAt,
        deleted_at: ht.deletedAt,
      })),
      rewards: result.rewards.map((r) => ({
        id: r.id,
        user_id: "",
        name: r.name,
        description: r.description,
        created_at: r.createdAt,
        updated_at: r.updatedAt,
        deleted_at: r.deletedAt,

        max_daily_frequency: r.maxDailyFrequency,
        damage_rank: r.damageRank,
      })),
      rewardTags: result.rewardTags.map((rt) => ({
        reward_id: rt.rewardId,
        tag_id: rt.tagId,
        user_id: "",
        created_at: rt.createdAt,
        updated_at: rt.updatedAt,
        deleted_at: rt.deletedAt,
      })),
      balance: {
        tofu_balance: result.balance.tofuBalance,
      },
      server_time: result.serverTime,
      email: result.email,
      isPremium: result.isPremium,
    };
  }
}

export const api = new ApiClient();
