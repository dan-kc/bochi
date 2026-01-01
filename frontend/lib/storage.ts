import { Platform } from "react-native";
import type { AuthTokens } from "./api";

const TOKENS_KEY = "auth_tokens";

// Storage abstraction that uses localStorage on web
// For native platforms, you should install expo-secure-store and use it here
const storage = {
  async getItem(key: string): Promise<string | null> {
    if (Platform.OS === "web") {
      return localStorage.getItem(key);
    }
    // For native, you would use SecureStore:
    // return await SecureStore.getItemAsync(key);
    return null;
  },

  async setItem(key: string, value: string): Promise<void> {
    if (Platform.OS === "web") {
      localStorage.setItem(key, value);
      return;
    }
    // For native, you would use SecureStore:
    // await SecureStore.setItemAsync(key, value);
  },

  async removeItem(key: string): Promise<void> {
    if (Platform.OS === "web") {
      localStorage.removeItem(key);
      return;
    }
    // For native, you would use SecureStore:
    // await SecureStore.deleteItemAsync(key);
  },
};

export async function getStoredTokens(): Promise<AuthTokens | null> {
  const tokensJson = await storage.getItem(TOKENS_KEY);
  if (!tokensJson) return null;

  try {
    return JSON.parse(tokensJson) as AuthTokens;
  } catch {
    return null;
  }
}

export async function storeTokens(tokens: AuthTokens): Promise<void> {
  await storage.setItem(TOKENS_KEY, JSON.stringify(tokens));
}

export async function clearTokens(): Promise<void> {
  await storage.removeItem(TOKENS_KEY);
}
