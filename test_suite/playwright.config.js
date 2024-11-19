// @ts-check
const { defineConfig, devices } = require("@playwright/test");

module.exports = defineConfig({
  workers: 1,
  timeout: 3000,
  testDir: "./tests",
  fullyParallel: true,
  reporter: "html",
  use: {
    baseURL: "http://server",
  },

  projects: [
    {
      name: "API tests",
      use: {},
    },
  ],
});
