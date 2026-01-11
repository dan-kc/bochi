import { Platform } from "react-native";
import * as SecureStore from "expo-secure-store";
import type { AuthTokens } from "./api";

const TOKENS_KEY = "auth_tokens";
const USER_INFO_KEY = "auth_user_info";
const isWeb = Platform.OS === "web";

// User info stored on web (no sensitive tokens)
export interface StoredUserInfo {
  userId: string;
  expiresAt: number; // Unix timestamp for scheduling refresh
}

// Storage abstraction:
// - Web: localStorage for user info only (userId, expiresAt)
//        Actual auth uses HttpOnly cookies (XSS can't steal session)
// - Native: SecureStore for full tokens (used for Authorization header)

// ============ Native-only: Full token storage ============

export async function getStoredTokens(): Promise<AuthTokens | null> {
  // Only used on native - web uses cookies
  if (isWeb) {
    return null;
  }
  const tokensJson = await SecureStore.getItemAsync(TOKENS_KEY);
  if (!tokensJson) return null;

  try {
    return JSON.parse(tokensJson) as AuthTokens;
  } catch {
    return null;
  }
}

export async function storeTokens(tokens: AuthTokens): Promise<void> {
  // Only store on native - web uses cookies
  if (isWeb) {
    return;
  }
  await SecureStore.setItemAsync(TOKENS_KEY, JSON.stringify(tokens));
}

export async function clearTokens(): Promise<void> {
  // Only used on native
  if (isWeb) {
    return;
  }
  await SecureStore.deleteItemAsync(TOKENS_KEY);
}

// ============ Web-only: User info storage (no tokens) ============

export async function getStoredUserInfo(): Promise<StoredUserInfo | null> {
  if (!isWeb) {
    return null;
  }
  const infoJson = localStorage.getItem(USER_INFO_KEY);
  if (!infoJson) return null;

  try {
    return JSON.parse(infoJson) as StoredUserInfo;
  } catch {
    return null;
  }
}

export async function storeUserInfo(info: StoredUserInfo): Promise<void> {
  if (!isWeb) {
    return;
  }
  localStorage.setItem(USER_INFO_KEY, JSON.stringify(info));
}

export async function clearUserInfo(): Promise<void> {
  if (!isWeb) {
    return;
  }
  localStorage.removeItem(USER_INFO_KEY);
}

// ============ Platform-agnostic helpers ============

export function isWebPlatform(): boolean {
  return isWeb;
}
