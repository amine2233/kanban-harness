import js from '@eslint/js'
import prettier from 'eslint-config-prettier'
import reactHooks from 'eslint-plugin-react-hooks'
import reactRefresh from 'eslint-plugin-react-refresh'
import globals from 'globals'
import tseslint from 'typescript-eslint'

export default tseslint.config(
  { ignores: ['dist', 'coverage', 'node_modules', 'website'] },
  js.configs.recommended,
  tseslint.configs.strictTypeChecked,
  tseslint.configs.stylisticTypeChecked,
  reactHooks.configs.flat.recommended,
  reactRefresh.configs.vite,
  {
    languageOptions: {
      globals: globals.browser,
      parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname },
    },
    rules: {
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/consistent-type-imports': 'error',
    },
  },
  // Layering: app → state → kanban-model; app → design-system. Nothing points the other way.
  layer('packages/kanban-model/src/**', [
    forbid(
      'react',
      'react-dom',
      'react-redux',
      '@reduxjs/toolkit',
      '@mvp/state',
      '@mvp/design-system',
    ),
    forbidPattern('@/*', 'the domain package must not reach into the app'),
  ]),
  layer('packages/design-system/src/**', [
    forbid('react-redux', '@reduxjs/toolkit', '@mvp/state', '@mvp/kanban-model'),
    forbidPattern('@/*', 'the design system must not reach into the app'),
  ]),
  layer('packages/state/src/**', [
    forbid('react', 'react-dom', '@mvp/design-system'),
    forbidPattern('@/*', 'the state package must not reach into the app'),
  ]),
  layer('src/**', [
    forbidPattern('@mvp/*/src/*', 'import a package by its name, never its files'),
    forbidPattern('../../packages/*', 'import a package by its name, never its path'),
  ]),
  { files: ['**/*.js'], extends: [tseslint.configs.disableTypeChecked] },
  prettier,
)

function layer(files, restrictions) {
  const paths = restrictions.flatMap((r) => r.paths ?? [])
  const patterns = restrictions.flatMap((r) => r.patterns ?? [])
  return { files: [files], rules: { 'no-restricted-imports': ['error', { paths, patterns }] } }
}

function forbid(...names) {
  return {
    paths: names.map((name) => ({ name, message: `${name} is not allowed in this package` })),
  }
}

function forbidPattern(group, message) {
  return { patterns: [{ group: [group], message }] }
}
