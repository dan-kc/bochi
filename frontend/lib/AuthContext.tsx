import {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  useRef,
  type ReactNode,
} from "react";
import { api, type AuthTokens, type ApiError } from "./api";
import { getStoredTokens, storeTokens, clearTokens } from "./storage";

interface User {
  id: string;
}

interface AuthContextType {
  user: User | null;
  isLoading: boolean;
  register: (email: string, password: string) => Promise<void>;
  login: (email: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | null>(null);

function parseJwtPayload(token: string): { sub?: string; exp?: number } | null {
  try {
    const base64Payload = token.split(".")[1];
    const payload = atob(base64Payload);
    return JSON.parse(payload);
  } catch {
    return null;
  }
}

function getUserFromTokens(tokens: AuthTokens): User | null {
  const payload = parseJwtPayload(tokens.accessToken);
  if (payload?.sub) {
    return {
      id: payload.sub,
    };
  }
  return null;
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const refreshTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const clearRefreshTimeout = useCallback(() => {
    if (refreshTimeoutRef.current) {
      clearTimeout(refreshTimeoutRef.current);
      refreshTimeoutRef.current = null;
    }
  }, []);

  const scheduleTokenRefresh = useCallback(
    (tokens: AuthTokens, performRefresh: (refreshToken: string) => Promise<void>) => {
      clearRefreshTimeout();

      const payload = parseJwtPayload(tokens.accessToken);
      if (!payload?.exp) {
        console.log("[Auth] No exp claim in token, skipping refresh schedule");
        return;
      }

      const expiresAt = payload.exp * 1000;
      const refreshAt = expiresAt - 60_000; // Refresh 1 minute before expiry
      const delay = refreshAt - Date.now();

      if (delay <= 0) {
        console.log("[Auth] Token already expired or expiring soon, refreshing now");
        performRefresh(tokens.refreshToken);
        return;
      }

      console.log(`[Auth] Scheduling token refresh in ${Math.round(delay / 1000)}s`);
      refreshTimeoutRef.current = setTimeout(() => {
        performRefresh(tokens.refreshToken);
      }, delay);
    },
    [clearRefreshTimeout],
  );

  const performTokenRefresh = useCallback(
    async (refreshToken: string) => {
      try {
        const newTokens = await api.refreshTokens(refreshToken);
        await storeTokens(newTokens);
        setUser(getUserFromTokens(newTokens));
        console.log("[Auth] Token refresh succeeded");
        scheduleTokenRefresh(newTokens, performTokenRefresh);
      } catch (error) {
        const apiError = error as ApiError;
        const isAuthError = apiError.status === 401;
        if (isAuthError) {
          console.log("[Auth] Token refresh error:", apiError.status, apiError.errors);
          clearRefreshTimeout();
          await clearTokens();
          setUser(null);
        } else {
          console.log("[Auth] Token refresh failed (keeping tokens):", error);
          // Retry in 1 minute on network errors
          refreshTimeoutRef.current = setTimeout(async () => {
            const tokens = await getStoredTokens();
            if (tokens) {
              performTokenRefresh(tokens.refreshToken);
            }
          }, 60_000);
        }
      }
    },
    [scheduleTokenRefresh, clearRefreshTimeout],
  );

  useEffect(() => {
    async function loadStoredAuth() {
      try {
        const tokens = await getStoredTokens();
        if (tokens) {
          console.log("[Auth] Stored tokens found");
          const user = getUserFromTokens(tokens);
          console.log("[Auth] User from tokens:", user);
          if (user) {
            setUser(user);
          }
          await performTokenRefresh(tokens.refreshToken);
        }
      } finally {
        setIsLoading(false);
      }
    }

    loadStoredAuth();

    return () => {
      clearRefreshTimeout();
    };
  }, [performTokenRefresh, clearRefreshTimeout]);

  const register = useCallback(
    async (email: string, password: string) => {
      const tokens = await api.register(email, password);
      await storeTokens(tokens);
      const user = getUserFromTokens(tokens);
      if (!user) {
        throw new Error("Failed to get user from tokens");
      }
      setUser(user);
      scheduleTokenRefresh(tokens, performTokenRefresh);
    },
    [scheduleTokenRefresh, performTokenRefresh],
  );

  const login = useCallback(
    async (email: string, password: string) => {
      const tokens = await api.login(email, password);
      await storeTokens(tokens);
      const user = getUserFromTokens(tokens);
      if (!user) {
        throw new Error("Failed to get user from tokens");
      }
      setUser(user);
      scheduleTokenRefresh(tokens, performTokenRefresh);
    },
    [scheduleTokenRefresh, performTokenRefresh],
  );

  const logout = useCallback(async () => {
    clearRefreshTimeout();
    try {
      const tokens = await getStoredTokens();
      if (tokens) {
        await api.logout(tokens.refreshToken);
      }
    } catch {
      // Logout API call failed, but we still want to clear local state
    } finally {
      await clearTokens();
      setUser(null);
    }
  }, [clearRefreshTimeout]);

  return (
    <AuthContext.Provider value={{ user, isLoading, register, login, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextType {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error("useAuth must be used within an AuthProvider");
  }
  return context;
}
