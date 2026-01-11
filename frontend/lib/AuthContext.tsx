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
import {
  getStoredTokens,
  storeTokens,
  clearTokens,
  getStoredUserInfo,
  storeUserInfo,
  clearUserInfo,
  isWebPlatform,
  type StoredUserInfo,
} from "./storage";

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

function getUserInfoFromTokens(tokens: AuthTokens): StoredUserInfo | null {
  const payload = parseJwtPayload(tokens.accessToken);
  if (payload?.sub && payload?.exp) {
    return {
      userId: payload.sub,
      expiresAt: payload.exp,
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
    (
      expiresAtSeconds: number,
      refreshToken: string | undefined,
      performRefresh: (refreshToken?: string) => Promise<void>,
    ) => {
      clearRefreshTimeout();

      const expiresAt = expiresAtSeconds * 1000;
      const refreshAt = expiresAt - 60_000; // Refresh 1 minute before expiry
      const delay = refreshAt - Date.now();

      if (delay <= 0) {
        console.log("[Auth] Token already expired or expiring soon, refreshing now");
        performRefresh(refreshToken);
        return;
      }

      console.log(`[Auth] Scheduling token refresh in ${Math.round(delay / 1000)}s`);
      refreshTimeoutRef.current = setTimeout(() => {
        performRefresh(refreshToken);
      }, delay);
    },
    [clearRefreshTimeout],
  );

  const performTokenRefresh = useCallback(
    async (refreshToken?: string) => {
      try {
        const newTokens = await api.refreshTokens(refreshToken);
        const userInfo = getUserInfoFromTokens(newTokens);
        const user = getUserFromTokens(newTokens);

        if (isWebPlatform()) {
          // Web: store only user info, cookies handle auth
          if (userInfo) {
            await storeUserInfo(userInfo);
          }
        } else {
          // Native: store full tokens
          await storeTokens(newTokens);
        }

        setUser(user);
        console.log("[Auth] Token refresh succeeded");

        if (userInfo) {
          scheduleTokenRefresh(userInfo.expiresAt, newTokens.refreshToken, performTokenRefresh);
        }
      } catch (error) {
        const apiError = error as ApiError;
        const isAuthError = apiError.status === 401;
        if (isAuthError) {
          console.log("[Auth] Token refresh error:", apiError.status, apiError.errors);
          clearRefreshTimeout();
          if (isWebPlatform()) {
            await clearUserInfo();
          } else {
            await clearTokens();
          }
          setUser(null);
        } else {
          console.log("[Auth] Token refresh failed (keeping session):", error);
          // Retry in 1 minute on network errors
          refreshTimeoutRef.current = setTimeout(async () => {
            if (isWebPlatform()) {
              // On web, just retry - cookie is still there
              performTokenRefresh();
            } else {
              const tokens = await getStoredTokens();
              if (tokens) {
                performTokenRefresh(tokens.refreshToken);
              }
            }
          }, 60_000);
        }
      }
    },
    [scheduleTokenRefresh, clearRefreshTimeout],
  );

  useEffect(() => {
    let isMounted = true;

    async function loadStoredAuth() {
      try {
        if (isWebPlatform()) {
          // Web: check for stored user info, then try to refresh (cookie handles auth)
          const userInfo = await getStoredUserInfo();
          if (userInfo && isMounted) {
            console.log("[Auth] Stored user info found");
            setUser({ id: userInfo.userId });
            // Try to refresh - cookie will be sent automatically
            if (isMounted) {
              await performTokenRefresh();
            }
          }
        } else {
          // Native: check for stored tokens
          const tokens = await getStoredTokens();
          if (tokens && isMounted) {
            console.log("[Auth] Stored tokens found");
            const user = getUserFromTokens(tokens);
            console.log("[Auth] User from tokens:", user);
            if (user) {
              setUser(user);
            }
            // Only refresh if still mounted (prevents double refresh in StrictMode)
            if (isMounted) {
              await performTokenRefresh(tokens.refreshToken);
            }
          }
        }
      } finally {
        if (isMounted) {
          setIsLoading(false);
        }
      }
    }

    loadStoredAuth();

    // This cleanup function will rarely execute because the context provider
    // wraps the whole app. This means it will never unmount unless the user
    // quits the app. So in production it will never unmount, but in local
    // development it may, because of HMR. Also this is still good to have
    // in case of a refactor in future.
    return () => {
      isMounted = false;
      clearRefreshTimeout();
    };
  }, [performTokenRefresh, clearRefreshTimeout]);

  const register = useCallback(
    async (email: string, password: string) => {
      const tokens = await api.register(email, password);
      const userInfo = getUserInfoFromTokens(tokens);
      const user = getUserFromTokens(tokens);

      if (!user || !userInfo) {
        throw new Error("Failed to get user from tokens");
      }

      if (isWebPlatform()) {
        // Web: store only user info, cookies handle auth
        await storeUserInfo(userInfo);
      } else {
        // Native: store full tokens
        await storeTokens(tokens);
      }

      setUser(user);
      scheduleTokenRefresh(userInfo.expiresAt, tokens.refreshToken, performTokenRefresh);
    },
    [scheduleTokenRefresh, performTokenRefresh],
  );

  const login = useCallback(
    async (email: string, password: string) => {
      const tokens = await api.login(email, password);
      const userInfo = getUserInfoFromTokens(tokens);
      const user = getUserFromTokens(tokens);

      if (!user || !userInfo) {
        throw new Error("Failed to get user from tokens");
      }

      if (isWebPlatform()) {
        // Web: store only user info, cookies handle auth
        await storeUserInfo(userInfo);
      } else {
        // Native: store full tokens
        await storeTokens(tokens);
      }

      setUser(user);
      scheduleTokenRefresh(userInfo.expiresAt, tokens.refreshToken, performTokenRefresh);
    },
    [scheduleTokenRefresh, performTokenRefresh],
  );

  const logout = useCallback(async () => {
    clearRefreshTimeout();
    try {
      if (isWebPlatform()) {
        // Web: cookie sent automatically
        await api.logout();
      } else {
        const tokens = await getStoredTokens();
        if (tokens) {
          await api.logout(tokens.refreshToken);
        }
      }
    } catch {
      // Logout API call failed, but we still want to clear local state
    } finally {
      if (isWebPlatform()) {
        await clearUserInfo();
      } else {
        await clearTokens();
      }
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
