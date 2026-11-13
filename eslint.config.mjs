import js from '@eslint/js';
import {defineConfig} from 'eslint/config';
import globals from 'globals';
import tseslint from 'typescript-eslint';

export default defineConfig(
  {
    files: ['scripts/**/*.mjs', 'sdk/web/test/**/*.mjs', 'eslint.config.mjs'],
    extends: [js.configs.recommended],
    languageOptions: {globals: globals.node},
  },
  {
    files: ['examples/web/*.js'],
    extends: [js.configs.recommended],
    languageOptions: {globals: globals.worker},
  },
  {
    files: ['sdk/web/src/**/*.ts', 'examples/web/**/*.ts', 'tests/e2e/**/*.ts', 'playwright.config.ts'],
    extends: [js.configs.recommended, tseslint.configs.recommended],
  },
);
