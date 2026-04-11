import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Use globals (describe, it, expect, vi) without importing
    globals: true,

    // Test environment
    environment: "node", // Use "jsdom" for browser/React testing

    // File patterns
    include: ["src/**/*.{test,spec}.{ts,tsx}", "tests/**/*.{test,spec}.{ts,tsx}"],
    exclude: ["node_modules", "dist", "**/*.d.ts"],

    // Setup files run before each test file
    setupFiles: ["./tests/setup.ts"],

    // Timeout per test (ms)
    testTimeout: 10_000,

    // Retry flaky tests
    retry: 0,

    // Reporter
    reporters: process.env.CI ? ["verbose", "junit"] : ["verbose"],
    outputFile: {
      junit: "./test-results/junit.xml",
    },

    // Coverage configuration
    coverage: {
      provider: "v8",
      enabled: false, // Enable explicitly with --coverage flag
      reporter: ["text", "html", "lcov", "json-summary"],
      reportsDirectory: "./coverage",

      // Source files to include
      include: ["src/**/*.{ts,tsx}"],
      exclude: [
        "src/**/*.d.ts",
        "src/**/*.test.{ts,tsx}",
        "src/**/*.spec.{ts,tsx}",
        "src/**/index.ts", // re-export barrels
        "src/**/*.types.ts",
      ],

      // Thresholds — CI will fail if below these
      thresholds: {
        lines: 80,
        functions: 80,
        branches: 80,
        statements: 80,

        // Per-file thresholds (stricter for core business logic)
        perFile: false,
      },

      // Fail build if any file drops below threshold
      skipFull: false,
    },

    // Type checking during test run (requires @vitest/eslint-plugin)
    typecheck: {
      enabled: false, // Enable for stricter CI: true
      tsconfig: "./tsconfig.json",
    },

    // Watch mode exclusions
    watchExclude: ["**/node_modules/**", "**/dist/**", "**/coverage/**"],
  },

  // Path aliases matching tsconfig.json
  resolve: {
    alias: {
      "@domain": new URL("./src/domain", import.meta.url).pathname,
      "@application": new URL("./src/application", import.meta.url).pathname,
      "@infrastructure": new URL("./src/infrastructure", import.meta.url).pathname,
      "@interfaces": new URL("./src/interfaces", import.meta.url).pathname,
    },
  },
});
