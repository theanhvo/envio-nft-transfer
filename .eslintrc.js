// @ts-check

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { defineConfig } = require("eslint-define-config")

/// <reference types="@eslint-types/typescript-eslint" />
/// <reference types="@eslint-types/import" />
/// <reference types="@eslint-types/prettier" />

module.exports = defineConfig({
  ignorePatterns: ["src/generated.ts"],
  extends: [
    "eslint:recommended",
    "airbnb-base",
    "plugin:prettier/recommended",
    "plugin:@typescript-eslint/recommended",
    "plugin:typescript-sort-keys/recommended",
  ],
  parser: "@typescript-eslint/parser",
  parserOptions: {
    project: true,
  },
  plugins: [
    "@typescript-eslint",
    "eslint-plugin-simple-import-sort",
    "eslint-plugin-unused-imports",
    "eslint-plugin-node",
    "eslint-plugin-security",
    "eslint-plugin-import",
    "unused-imports",
    "sort-destructure-keys",
    "typescript-sort-keys",
  ],
  rules: {
    "require-await": "error",
    "@typescript-eslint/no-floating-promises": "error",
    camelcase: "off",
    "sort-destructure-keys/sort-destructure-keys": 2,
    "import/prefer-default-export": "off",
    "import/extensions": "off",
    "prettier/prettier": [
      "error",
      {
        endOfLine: "auto",
        singleQuote: false,
        semi: false,
      },
    ],
    "@typescript-eslint/consistent-type-imports": "error", // Ensure `import type` is used when it's necessary
    "no-console": "warn", // will be managed by next.config.js in production
    "no-nested-ternary": "warn",
    "no-param-reassign": [
      "error",
      {
        props: false,
      },
    ],
    "no-plusplus": [
      "error",
      {
        allowForLoopAfterthoughts: true,
      },
    ],
    "no-undef": "off",
    "no-unused-vars": "off", // has problems with enums, prefer @typescript-eslint/no-unused-vars
    "@typescript-eslint/no-unused-vars": [
      process.env.NODE_ENV === "production" ? "error" : "warn",
      {
        args: "all",
        argsIgnorePattern: "^_",
        caughtErrors: "all",
        caughtErrorsIgnorePattern: "^_",
        destructuredArrayIgnorePattern: "^_",
        varsIgnorePattern: "^_",
        ignoreRestSiblings: true,
      },
    ],
    "simple-import-sort/imports": "error",
    "simple-import-sort/exports": "error",
    "no-shadow": "off",
    "@typescript-eslint/no-shadow": "error",
    "object-shorthand": ["error", "always"],
    "unused-imports/no-unused-imports": process.env.NODE_ENV === "production" ? "error" : "warn",
    "unused-imports/no-unused-vars": "off",
  },
  settings: {
    "import/parsers": {
      "@typescript-eslint/parser": [".ts", ".tsx"],
    },
    "import/resolver": {
      typescript: {
        alwaysTryTypes: true,
        project: "./tsconfig.json",
      },
    },
  },
})
