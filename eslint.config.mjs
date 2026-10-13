import nextPlugin from "@next/eslint-plugin-next";
import tsParser from "@typescript-eslint/parser";
import tsPlugin from "@typescript-eslint/eslint-plugin";

export default [{
  files: ["**/*.{js,jsx,ts,tsx}"],
  ignores: [".next/**", "out/**", "build/**", "next-env.d.ts"],
  languageOptions: { parser: tsParser, parserOptions: { ecmaFeatures: { jsx: true }, sourceType: "module" } },
  plugins: { "@next/next": nextPlugin, "@typescript-eslint": tsPlugin },
  rules: { ...nextPlugin.configs.recommended.rules, ...tsPlugin.configs.recommended.rules },
}];
