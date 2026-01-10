import {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  type ReactNode,
} from "react";
import { api, type AuthTokens } from "./api";
import { getStoredTokens, storeTokens, clearTokens } from "./storage";

interface User {
  id: string;
  email: string;
}

interface AuthContextType {
  user: User | null;
  isLoading: boolean;
  register: (email: string, password: string) => Promise<void>;
  login: (email: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | null>(null);

function parseJwtPayload(
  token: string,
): { sub?: string; email?: string } | null {
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
      email: payload.email ?? "", // Email not in JWT, will be empty
    };
  }
  return null;
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    async function loadStoredAuth() {
      try {
        const tokens = await getStoredTokens();
        console.log("[Auth] Stored tokens:", tokens ? "found" : "none");
        if (tokens) {
          // First, try to use existing tokens
          const user = getUserFromTokens(tokens);
          console.log("[Auth] User from tokens:", user);
          if (user) {
            setUser(user);
          }

          // Then try to refresh in the background
          try {
            const newTokens = await api.refreshTokens(tokens.refreshToken);
            await storeTokens(newTokens);
            setUser(getUserFromTokens(newTokens));
            console.log("[Auth] Token refresh succeeded");
          } catch (error) {
            console.log("[Auth] Token refresh failed:", error);
            // Only clear tokens if refresh was explicitly rejected (invalid token)
            // Don't clear on network errors - user can still use existing tokens
            const isAuthError =
              error &&
              typeof error === "object" &&
              "status" in error &&
              (error.status === 401 || error.status === 403);
            if (isAuthError) {
              console.log("[Auth] Clearing tokens due to auth error");
              await clearTokens();
              setUser(null);
            }
            // On network errors, keep existing tokens and user state
          }
        }
      } finally {
        setIsLoading(false);
      }
    }

    loadStoredAuth();
  }, []);

  const register = useCallback(async (email: string, password: string) => {
    const tokens = await api.register(email, password);
    await storeTokens(tokens);
    setUser(getUserFromTokens(tokens) ?? { id: email, email });
  }, []);

  const login = useCallback(async (email: string, password: string) => {
    const tokens = await api.login(email, password);
    await storeTokens(tokens);
    setUser(getUserFromTokens(tokens) ?? { id: email, email });
  }, []);

  const logout = useCallback(async () => {
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
  }, []);

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
