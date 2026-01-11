import { Platform } from "react-native";
import * as SecureStore from "expo-secure-store";
import type { AuthTokens } from "./api";

const TOKENS_KEY = "auth_tokens";

// Storage abstraction that uses localStorage on web and SecureStore on native
const storage = {
  async getItem(key: string): Promise<string | null> {
    if (Platform.OS === "web") {
      return localStorage.getItem(key);
    }
    return await SecureStore.getItemAsync(key);
  },

  async setItem(key: string, value: string): Promise<void> {
    if (Platform.OS === "web") {
      localStorage.setItem(key, value);
      return;
    }
    await SecureStore.setItemAsync(key, value);
  },

  async removeItem(key: string): Promise<void> {
    if (Platform.OS === "web") {
      localStorage.removeItem(key);
      return;
    }
    await SecureStore.deleteItemAsync(key);
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
