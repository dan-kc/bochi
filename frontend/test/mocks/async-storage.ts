// Mock for @react-native-async-storage/async-storage in Vitest tests
const storage: Record<string, string> = {};

export default {
  getItem: async (key: string): Promise<string | null> => {
    return storage[key] ?? null;
  },
  setItem: async (key: string, value: string): Promise<void> => {
    storage[key] = value;
  },
  removeItem: async (key: string): Promise<void> => {
    delete storage[key];
  },
  clear: async (): Promise<void> => {
    for (const key of Object.keys(storage)) {
      delete storage[key];
    }
  },
  getAllKeys: async (): Promise<string[]> => {
    return Object.keys(storage);
  },
  multiGet: async (
    keys: string[],
  ): Promise<readonly [string, string | null][]> => {
    return keys.map((key) => [key, storage[key] ?? null]);
  },
  multiSet: async (keyValuePairs: [string, string][]): Promise<void> => {
    for (const [key, value] of keyValuePairs) {
      storage[key] = value;
    }
  },
  multiRemove: async (keys: string[]): Promise<void> => {
    for (const key of keys) {
      delete storage[key];
    }
  },
};
