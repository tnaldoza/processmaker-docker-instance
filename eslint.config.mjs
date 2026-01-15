// ESLint Flat Config (ESLint 9+)
// This replaces the deprecated .eslintrc format
import js from "@eslint/js";
import globals from "globals";

export default [
	// Global ignores - these paths will not be linted
	{
		ignores: [
			"**/node_modules/**",
			"**/dist/**",
			"**/build/**",
			"**/.git/**",
			"**/coverage/**",
			"**/*.min.js",
			"**/package-lock.json",
			"**/pnpm-lock.yaml",
			"**/yarn.lock",
			"**/docs/**",
		],
	},

	// Base recommended rules from ESLint
	js.configs.recommended,

	// Configuration for ProcessMaker workflow scripts (.cjs files)
	// These have access to 'data' and 'config' globals provided by ProcessMaker
	{
		files: ["scripts/**/*.cjs"],
		languageOptions: {
			ecmaVersion: 2024,
			sourceType: "commonjs",
			globals: {
				...globals.node,
				...globals.es2021,
				// ProcessMaker provides these globals in workflow context
				data: "readonly",
				config: "readonly",
			},
			parserOptions: {
				ecmaFeatures: {
					impliedStrict: true,
					globalReturn: true, // Allow top-level return in CJS
				},
			},
		},
		rules: {
			// Same strict rules as other files
			"no-console": "error",
			"no-debugger": "error",
			"no-duplicate-imports": "error",
			"no-self-compare": "error",
			"no-template-curly-in-string": "warn",
			"no-unreachable-loop": "error",
			"no-unused-vars": [
				"error",
				{
					argsIgnorePattern: "^_",
					varsIgnorePattern: "^_",
				},
			],
			"require-atomic-updates": "error",
			eqeqeq: ["error", "always"],
			"no-eval": "error",
			"no-implied-eval": "error",
			"no-new-func": "error",
			"no-throw-literal": "error",
			"prefer-promise-reject-errors": "error",
			"no-var": "error",
			"prefer-const": "warn",
			"prefer-arrow-callback": "warn",
			"no-new-wrappers": "error",
			"no-script-url": "error",
			"no-sequences": "error",
			"array-callback-return": "error",
			"no-empty": ["error", { allowEmptyCatch: true }],
			"no-lonely-if": "warn",
			"object-shorthand": ["warn", "always"],
			"prefer-template": "warn",
			"no-restricted-globals": [
				"error",
				{
					name: "eval",
					message: "eval() is forbidden for security reasons",
				},
				{
					name: "console",
					message: "ProcessMaker forbids all console output. Return resolved promises or objects instead.",
				},
			],
			"no-restricted-properties": [
				"error",
				{
					object: "Math",
					property: "random",
					message: "Use crypto.randomBytes() for cryptographically secure random numbers",
				},
				{
					object: "console",
					property: "log",
					message: "ProcessMaker forbids console.log. Return resolved promises or objects instead.",
				},
				{
					object: "console",
					property: "error",
					message: "ProcessMaker forbids console.error. Return resolved promises or objects instead.",
				},
				{
					object: "console",
					property: "warn",
					message: "ProcessMaker forbids console.warn. Return resolved promises or objects instead.",
				},
				{
					object: "console",
					property: "info",
					message: "ProcessMaker forbids console.info. Return resolved promises or objects instead.",
				},
				{
					object: "console",
					property: "debug",
					message: "ProcessMaker forbids console.debug. Return resolved promises or objects instead.",
				},
			],
		},
	},

	// Configuration for all JavaScript files
	{
		files: ["**/*.js", "**/*.mjs", "**/*.cjs"],
		ignores: ["scripts/**/*.cjs"], // Exclude workflow scripts from this config

		languageOptions: {
			ecmaVersion: 2024,
			sourceType: "module",

			globals: {
				...globals.node,
				...globals.es2021,
			},

			parserOptions: {
				ecmaFeatures: {
					impliedStrict: true,
					globalReturn: true,
				},
			},
		},

		rules: {
			// These rules catch potential bugs and logic errors
			"no-console": "error", // ProcessMaker forbids ALL console output
			"no-debugger": "error", // Never commit debugger statements
			"no-duplicate-imports": "error", // Prevent duplicate imports
			"no-self-compare": "error", // x === x is always true
			"no-template-curly-in-string": "warn", // Catch ${} in regular strings
			"no-unreachable-loop": "error", // Loops that only run once
			"no-unused-vars": [
				"error",
				{
					argsIgnorePattern: "^_", // Allow unused vars prefixed with _
					varsIgnorePattern: "^_",
				},
			],
			"require-atomic-updates": "error", // Race condition in async code
			// These promote better coding patterns
			eqeqeq: ["error", "always"], // Require === and !== (not == or !=)
			"no-eval": "error", // eval() is dangerous
			"no-implied-eval": "error", // setTimeout with string is eval
			"no-new-func": "error", // new Function() is eval-like
			"no-throw-literal": "error", // throw new Error(), not strings
			"prefer-promise-reject-errors": "error", // Reject with Error objects
			"no-var": "error", // Use let/const, never var
			"prefer-const": "warn", // Use const when variable isn't reassigned
			"prefer-arrow-callback": "warn", // Use arrow functions for callbacks
			// These prevent security vulnerabilities
			"no-new-wrappers": "error", // Don't use new String(), new Number(), etc.
			"no-script-url": "error", // No javascript: URLs
			"no-sequences": "error", // Prevent comma operator misuse
			// These maintain consistent code formatting
			// Note: We already use .prettierrc for formatting
			// These rules only catch logical style issues
			"array-callback-return": "error", // Array methods must return
			"no-empty": ["error", { allowEmptyCatch: true }], // No empty blocks
			"no-lonely-if": "warn", // else { if } should be else if
			"object-shorthand": ["warn", "always"], // {a: a} should be {a}
			"prefer-template": "warn", // Use `${x}` not "string" + x
			// Custom rules for ProcessMaker environment
			"no-restricted-globals": [
				"error",
				{
					name: "eval",
					message: "eval() is forbidden for security reasons",
				},
				{
					name: "console",
					message: "ProcessMaker forbids all console output. Return resolved promises or objects instead.",
				},
			],
			"no-restricted-properties": [
				"error",
				{
					object: "console",
					property: "log",
					message: "ProcessMaker forbids console.log. Return resolved promises or objects instead.",
				},
				{
					object: "console",
					property: "error",
					message: "ProcessMaker forbids console.error. Return resolved promises or objects instead.",
				},
				{
					object: "console",
					property: "warn",
					message: "ProcessMaker forbids console.warn. Return resolved promises or objects instead.",
				},
				{
					object: "console",
					property: "info",
					message: "ProcessMaker forbids console.info. Return resolved promises or objects instead.",
				},
				{
					object: "console",
					property: "debug",
					message: "ProcessMaker forbids console.debug. Return resolved promises or objects instead.",
				},
			],
		},
	},

	// Configuration specific to package files
	{
		files: ["packages/**/*.js"],
		rules: {
			"no-console": "error", // Strict error for library code
		},
	},

	// Configuration for test files
	{
		files: ["**/*.test.js", "**/*.spec.js", "**/__tests__/**/*.js"],
		languageOptions: {
			globals: {
				...globals.jest,
				...globals.mocha,
			},
		},
		rules: {
			"no-console": "off", // Allow console in tests
			"no-restricted-globals": "off", // Allow console in tests
			"no-restricted-properties": "off", // Allow console in tests
		},
	},
];
