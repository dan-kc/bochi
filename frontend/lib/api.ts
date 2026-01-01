import type { Task } from "./task";
import type { SyncPullResponse, SyncPushResponse } from "./sync/types";
import { getStoredTokens } from "./storage";

const API_PROTOCOL = process.env.EXPO_PUBLIC_API_PROTOCOL || "https";
const API_HOST = process.env.EXPO_PUBLIC_API_HOST || "localhost";
const API_PORT = process.env.EXPO_PUBLIC_API_PORT || "8500";
const API_BASE = `${API_PROTOCOL}://${API_HOST}:${API_PORT}`;

export interface AuthTokens {
  refresh_token: string;
  access_token: string;
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
      throw data as ApiError;
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
    return this.request<AuthTokens>("/auth/refresh_tokens", {
      method: "POST",
      body: JSON.stringify({ refresh_token: refreshToken }),
    });
  }

  async logout(refreshToken: string): Promise<{ success: boolean }> {
    return this.request<{ success: boolean }>("/auth/logout", {
      method: "POST",
      body: JSON.stringify({ refresh_token: refreshToken }),
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
        Authorization: `Bearer ${tokens.access_token}`,
      },
    });
  }

  // ============ Task sync endpoints ============

  async pullTasks(since: string | null): Promise<SyncPullResponse> {
    const query = since ? `?since=${encodeURIComponent(since)}` : "";
    return this.authenticatedRequest<SyncPullResponse>(`/tasks/sync${query}`, {
      method: "GET",
    });
  }

  async pushTasks(tasks: Task[]): Promise<SyncPushResponse> {
    return this.authenticatedRequest<SyncPushResponse>("/tasks/sync", {
      method: "POST",
      body: JSON.stringify({ tasks }),
    });
  }
}

export const api = new ApiClient();
