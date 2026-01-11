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
  getOrCreateDeviceId,
  type StoredUserInfo,
} from "./storage";
import { taskStore } from "./store/taskStore";

interface User {
  id: string;
  isAnonymous: boolean;
}

interface AuthContextType {
  user: User | null;
  isLoading: boolean;
  isAnonymous: boolean;
  register: (email: string, password: string) => Promise<void>;
  login: (email: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
  claimAccount: (email: string, password: string) => Promise<void>;
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

function getUserFromTokens(tokens: AuthTokens, isAnonymous: boolean): User | null {
  const payload = parseJwtPayload(tokens.accessToken);
  if (payload?.sub) {
    return {
      id: payload.sub,
      isAnonymous,
    };
  }
  return null;
}

function getUserInfoFromTokens(
  tokens: AuthTokens,
  isAnonymous: boolean,
): StoredUserInfo | null {
  const payload = parseJwtPayload(tokens.accessToken);
  if (payload?.sub && payload?.exp) {
    return {
      userId: payload.sub,
      expiresAt: payload.exp,
      isAnonymous,
    };
  }
  return null;
}

// Token storage with anonymous flag for native
interface ExtendedTokens extends AuthTokens {
  isAnonymous: boolean;
}

async function getStoredExtendedTokens(): Promise<ExtendedTokens | null> {
  if (isWebPlatform()) {
    return null;
  }
  const tokens = await getStoredTokens();
  if (!tokens) return null;

  // Check localStorage for anonymous flag (fallback to false)
  // We store this separately because SecureStore is for sensitive data
  try {
    const { default: AsyncStorage } = await import(
      "@react-native-async-storage/async-storage"
    );
    const isAnonymousStr = await AsyncStorage.getItem("auth_is_anonymous");
    const isAnonymous = isAnonymousStr === "true";
    return { ...tokens, isAnonymous };
  } catch {
    return { ...tokens, isAnonymous: false };
  }
}

async function storeExtendedTokens(tokens: ExtendedTokens): Promise<void> {
  if (isWebPlatform()) {
    return;
  }
  await storeTokens(tokens);
  // Store anonymous flag separately
  try {
    const { default: AsyncStorage } = await import(
      "@react-native-async-storage/async-storage"
    );
    await AsyncStorage.setItem("auth_is_anonymous", tokens.isAnonymous.toString());
  } catch {
    // Ignore storage errors
  }
}

async function clearExtendedTokens(): Promise<void> {
  if (isWebPlatform()) {
    return;
  }
  await clearTokens();
  try {
    const { default: AsyncStorage } = await import(
      "@react-native-async-storage/async-storage"
    );
    await AsyncStorage.removeItem("auth_is_anonymous");
  } catch {
    // Ignore storage errors
  }
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

        // Get current anonymous status from stored data
        let isAnonymous = false;
        if (isWebPlatform()) {
          const stored = await getStoredUserInfo();
          isAnonymous = stored?.isAnonymous ?? false;
        } else {
          const stored = await getStoredExtendedTokens();
          isAnonymous = stored?.isAnonymous ?? false;
        }

        const userInfo = getUserInfoFromTokens(newTokens, isAnonymous);
        const user = getUserFromTokens(newTokens, isAnonymous);

        if (isWebPlatform()) {
          // Web: store only user info, cookies handle auth
          if (userInfo) {
            await storeUserInfo(userInfo);
          }
        } else {
          // Native: store full tokens
          await storeExtendedTokens({ ...newTokens, isAnonymous });
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
            await clearExtendedTokens();
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

  // Anonymous authentication
  const performAnonymousAuth = useCallback(async (): Promise<void> => {
    try {
      const deviceId = await getOrCreateDeviceId();
      console.log("[Auth] Performing anonymous auth with device ID:", deviceId);

      const tokens = await api.anonymousAuth(deviceId);
      const userInfo = getUserInfoFromTokens(tokens, true);
      const user = getUserFromTokens(tokens, true);

      if (!user || !userInfo) {
        throw new Error("Failed to get user from tokens");
      }

      if (isWebPlatform()) {
        await storeUserInfo(userInfo);
      } else {
        await storeExtendedTokens({ ...tokens, isAnonymous: true });
      }

      // Migrate any tasks created while offline (with "local-user" ID) to this new user
      await taskStore.migrateLocalUserTasks(user.id);

      setUser(user);
      console.log("[Auth] Anonymous auth succeeded");
      scheduleTokenRefresh(userInfo.expiresAt, tokens.refreshToken, performTokenRefresh);
    } catch (error) {
      console.error("[Auth] Anonymous auth failed:", error);
      // Don't throw - just leave user as null, they can retry
    }
  }, [scheduleTokenRefresh, performTokenRefresh]);

  useEffect(() => {
    let isMounted = true;

    async function loadStoredAuth() {
      try {
        if (isWebPlatform()) {
          // Web: check for stored user info, then try to refresh (cookie handles auth)
          const userInfo = await getStoredUserInfo();
          if (userInfo && isMounted) {
            console.log("[Auth] Stored user info found, isAnonymous:", userInfo.isAnonymous);
            setUser({ id: userInfo.userId, isAnonymous: userInfo.isAnonymous });
            // Try to refresh - cookie will be sent automatically
            if (isMounted) {
              await performTokenRefresh();
            }
          } else if (isMounted) {
            // No stored auth - perform anonymous auth
            console.log("[Auth] No stored auth, performing anonymous auth");
            await performAnonymousAuth();
          }
        } else {
          // Native: check for stored tokens
          const tokens = await getStoredExtendedTokens();
          if (tokens && isMounted) {
            console.log("[Auth] Stored tokens found, isAnonymous:", tokens.isAnonymous);
            const user = getUserFromTokens(tokens, tokens.isAnonymous);
            console.log("[Auth] User from tokens:", user);
            if (user) {
              setUser(user);
            }
            // Only refresh if still mounted (prevents double refresh in StrictMode)
            if (isMounted) {
              await performTokenRefresh(tokens.refreshToken);
            }
          } else if (isMounted) {
            // No stored auth - perform anonymous auth
            console.log("[Auth] No stored auth, performing anonymous auth");
            await performAnonymousAuth();
          }
        }
      } finally {
        if (isMounted) {
          setIsLoading(false);
        }
      }
    }

    loadStoredAuth();

    return () => {
      isMounted = false;
      clearRefreshTimeout();
    };
  }, [performTokenRefresh, performAnonymousAuth, clearRefreshTimeout]);

  // Retry anonymous auth when connectivity is restored and user is null
  useEffect(() => {
    if (isWebPlatform()) {
      const handleOnline = () => {
        if (!user && !isLoading) {
          console.log("[Auth] Connection restored, retrying anonymous auth");
          performAnonymousAuth();
        }
      };

      window.addEventListener("online", handleOnline);
      return () => window.removeEventListener("online", handleOnline);
    } else {
      // Native: use NetInfo to detect when connectivity is restored
      let unsubscribe: (() => void) | null = null;
      let wasConnected = false;

      import("@react-native-community/netinfo").then((NetInfo) => {
        unsubscribe = NetInfo.default.addEventListener((state) => {
          const isConnected = state.isConnected ?? false;

          // Only trigger when transitioning from offline to online
          if (isConnected && !wasConnected && !user && !isLoading) {
            console.log("[Auth] Connection restored, retrying anonymous auth");
            performAnonymousAuth();
          }

          wasConnected = isConnected;
        });
      });

      return () => {
        unsubscribe?.();
      };
    }
  }, [user, isLoading, performAnonymousAuth]);

  const register = useCallback(
    async (email: string, password: string) => {
      const tokens = await api.register(email, password);
      const userInfo = getUserInfoFromTokens(tokens, false);
      const user = getUserFromTokens(tokens, false);

      if (!user || !userInfo) {
        throw new Error("Failed to get user from tokens");
      }

      if (isWebPlatform()) {
        await storeUserInfo(userInfo);
      } else {
        await storeExtendedTokens({ ...tokens, isAnonymous: false });
      }

      setUser(user);
      scheduleTokenRefresh(userInfo.expiresAt, tokens.refreshToken, performTokenRefresh);
    },
    [scheduleTokenRefresh, performTokenRefresh],
  );

  const login = useCallback(
    async (email: string, password: string) => {
      const tokens = await api.login(email, password);
      const userInfo = getUserInfoFromTokens(tokens, false);
      const user = getUserFromTokens(tokens, false);

      if (!user || !userInfo) {
        throw new Error("Failed to get user from tokens");
      }

      if (isWebPlatform()) {
        await storeUserInfo(userInfo);
      } else {
        await storeExtendedTokens({ ...tokens, isAnonymous: false });
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
        // Clear all localStorage for a fresh start
        localStorage.clear();
      } else {
        await clearExtendedTokens();
      }

      // After logout, perform anonymous auth to get a new anonymous account
      // Don't set user to null first - let performAnonymousAuth update directly
      // to avoid a flash of the "no user" UI state
      await performAnonymousAuth();
    }
  }, [clearRefreshTimeout, performAnonymousAuth]);

  const claimAccount = useCallback(
    async (email: string, password: string) => {
      // Get current access token for the claim request
      let accessToken: string | undefined;
      if (!isWebPlatform()) {
        const tokens = await getStoredTokens();
        accessToken = tokens?.accessToken;
      }

      const tokens = await api.claimAccount(email, password, accessToken);
      const userInfo = getUserInfoFromTokens(tokens, false);
      const user = getUserFromTokens(tokens, false);

      if (!user || !userInfo) {
        throw new Error("Failed to get user from tokens");
      }

      if (isWebPlatform()) {
        await storeUserInfo(userInfo);
      } else {
        await storeExtendedTokens({ ...tokens, isAnonymous: false });
      }

      setUser(user);
      scheduleTokenRefresh(userInfo.expiresAt, tokens.refreshToken, performTokenRefresh);
    },
    [scheduleTokenRefresh, performTokenRefresh],
  );

  return (
    <AuthContext.Provider
      value={{
        user,
        isLoading,
        isAnonymous: user?.isAnonymous ?? false,
        register,
        login,
        logout,
        claimAccount,
      }}
    >
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
