// Mock for react-native in Vitest tests
export const Platform = {
  OS: "web",
  select: <T>(options: { web?: T; ios?: T; android?: T; default?: T }): T => {
    return (options.web ?? options.default) as T;
  },
};

export const AppState = {
  currentState: "active",
  addEventListener: () => ({ remove: () => {} }),
};
