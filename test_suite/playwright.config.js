// @ts-check
const { defineConfig, devices } = require("@playwright/test");

module.exports = defineConfig({
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
