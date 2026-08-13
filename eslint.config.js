import eslint from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  {
    ignores: ['node_modules/**', 'vendor/**', 'contracts/out/**', 'contracts/cache/**', 'web/dist/**'],
  },
  eslint.configs.recommended,
  {
    // Type-aware linting applies to our TypeScript sources only. This config file itself is
    // plain JS and is deliberately outside tsconfig's `include`, so the project service
    // cannot type it.
    files: ['**/*.ts'],
    extends: [...tseslint.configs.recommendedTypeChecked],
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      '@typescript-eslint/no-unused-vars': ['error', {argsIgnorePattern: '^_'}],
    },
  },
  {
    // Scripts and the worker are CLI tools — console output is the interface.
    files: ['scripts/**/*.ts', 'worker/**/*.ts'],
    rules: {'no-console': 'off'},
  },
);
