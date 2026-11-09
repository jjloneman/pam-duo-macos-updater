import type { Config } from "prettier";

import { LangVariant } from "sh-syntax";

const config: Config = {
  overrides: [
    /*
     * Everything under these paths is zsh, so route it to `prettier-plugin-sh`
     * explicitly.
     *
     * - Must specify `LangZsh`, since the bash parser fails on zsh syntax such
     *   as `${${name%/}:t}` and the `(N)` glob qualifier.
     */
    {
      files: [
        ".githooks/*",
        "bin/*",
        "lib/*.zsh",
        "libexec/*",
        "scripts/**/*.zsh",
        "test/**/*.zsh",
      ],
      options: { parser: "sh", variant: LangVariant.LangZsh },
    },
  ],
  plugins: ["prettier-plugin-sh"],
};

export default config;
