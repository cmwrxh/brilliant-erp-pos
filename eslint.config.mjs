import nextPlugin from "@next/eslint-plugin-next";

export default [{
  files: ["**/*.{js,jsx,ts,tsx}"],
  ignores: [".next/**", "out/**", "build/**", "next-env.d.ts"],
  plugins: { "@next/next": nextPlugin },
  rules: nextPlugin.configs.recommended.rules,
}];
