import astro from "eslint-plugin-astro";
import oxlint from "eslint-plugin-oxlint";

export default [
  ...astro.configs["flat/recommended"],
  {
    files: ["**/*.{js,ts,jsx,tsx,astro}"],
    rules: {
      "no-debugger": "error",
    },
  },
  ...oxlint.configs["flat/recommended"],
];
