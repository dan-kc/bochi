import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    include: ["lib/**/*.test.ts"],
    globals: true,
    alias: {
      "react-native": new URL("./test/mocks/react-native.ts", import.meta.url)
        .pathname,
      "@react-native-async-storage/async-storage": new URL(
        "./test/mocks/async-storage.ts",
        import.meta.url,
      ).pathname,
    },
  },
});
