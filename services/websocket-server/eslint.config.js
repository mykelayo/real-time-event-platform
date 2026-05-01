module.exports = [
  {
    files: ["src/**/*.js"],
    languageOptions: {
  ecmaVersion: 2022,
  sourceType: "commonjs",
  globals: {
    console:    "readonly",
    process:    "readonly",
    __dirname:  "readonly",
    require:    "readonly",
    module:     "writable",
    exports:    "writable",
  },
},
    rules: {
      "no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
      "no-console": "off",
      "semi": ["error", "always"],
      "quotes": ["error", "double"],
    },
  },
];