import astro from "eslint-plugin-astro";

export default [
  ...astro.configs["flat/recommended"],
  {
    files: ["**/*.{js,ts,jsx,tsx,astro}"],
    rules: {
      "no-debugger": "error",
    },
  },
];
