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
  const payload = parseJwtPayload(tokens.access_token);
  if (payload?.email) {
    // Use 'sub' claim as user ID, fallback to email
    return {
      id: payload.sub ?? payload.email,
      email: payload.email,
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
        if (tokens) {
          // Try to refresh tokens on app start
          try {
            const newTokens = await api.refreshTokens(tokens.refresh_token);
            await storeTokens(newTokens);
            setUser(getUserFromTokens(newTokens));
          } catch {
            // Refresh failed, clear stored tokens
            await clearTokens();
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
        await api.logout(tokens.refresh_token);
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
