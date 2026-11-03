import { defineConfig, globalIgnores } from "eslint/config";
import prettierRecommended from "eslint-plugin-prettier/recommended";
import tseslint from "typescript-eslint";

export default defineConfig(globalIgnores(["types/", "lib/"]), tseslint.configs.recommended, prettierRecommended);
