import { APP_THEMES, PRINT_TOKENS, type ThemeTokens } from "./theme";

/**
 * Theme files for the parts of Palee that cannot read the web's CSS: the
 * Android and iOS shells (splash, status bar, widgets), the shells' offline
 * pages and the API's emails and receipts. They are generated from
 * src/lib/theme.ts, so the theme still lives in one place:
 *
 *   npm run theme:native   (rewrites them after a theme change)
 *
 * native-theme.test.ts fails while any of them is out of date.
 */

const light = APP_THEMES.frost.tokens;
const dark = APP_THEMES.graphite.tokens;

const GENERATED = "Generated from apps/web/src/lib/theme.ts by `npm run theme:native`; do not edit.";

/** The tokens the native shells use, by their native name. */
const NATIVE_TOKENS: Record<string, keyof ThemeTokens> = {
  background: "bg",
  panel: "panel",
  text: "text",
  muted: "muted",
  border: "border",
  primary: "primary",
  primary_contrast: "primaryContrast",
  spark: "spark",
  spark_contrast: "sparkContrast",
};

const pascal = (name: string) => name.replace(/(^|_)([a-z])/g, (_match, _sep, letter: string) => letter.toUpperCase());
const androidColour = (hex: string) => `#FF${hex.replace("#", "").toUpperCase()}`;

function androidColours(tokens: ThemeTokens) {
  const rows = Object.entries(NATIVE_TOKENS).map(
    ([name, token]) => `    <color name="palee_${name}">${androidColour(tokens[token])}</color>`,
  );
  return `<?xml version="1.0" encoding="utf-8"?>\n<!-- ${GENERATED} -->\n<resources>\n${rows.join("\n")}\n</resources>\n`;
}

function iosColourSet(token: keyof ThemeTokens) {
  const components = (hex: string) => {
    const value = hex.replace("#", "");
    return {
      alpha: "1.000",
      blue: `0x${value.slice(4, 6)}`,
      green: `0x${value.slice(2, 4)}`,
      red: `0x${value.slice(0, 2)}`,
    };
  };
  const colour = (hex: string, appearance?: "dark") => ({
    ...(appearance ? { appearances: [{ appearance: "luminosity", value: appearance }] } : {}),
    color: { "color-space": "srgb", components: components(hex) },
    idiom: "universal",
  });
  return `${JSON.stringify({ colors: [colour(light[token]), colour(dark[token], "dark")], info: { author: "palee", version: 1 } }, null, 2)}\n`;
}

/** The arms-up mark (docs/brand/logo) on the page colour, for the iOS launch screen. */
function splashSvg(tokens: ThemeTokens) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1366 1366"><rect width="1366" height="1366" fill="${tokens.bg}"/><g transform="translate(563 573) scale(1.2)"><path d="M40 52 Q46 150 100 150 Q154 150 160 52" fill="none" stroke="${tokens.text}" stroke-width="26" stroke-linecap="round"/><circle cx="100" cy="88" r="24" fill="${tokens.primary}"/></g></svg>\n`;
}

function splashImageSet() {
  return `${JSON.stringify(
    {
      images: [
        { filename: "splash.svg", idiom: "universal" },
        { appearances: [{ appearance: "luminosity", value: "dark" }], filename: "splash-dark.svg", idiom: "universal" },
      ],
      info: { author: "palee", version: 1 },
      properties: { "preserves-vector-representation": true },
    },
    null,
    2,
  )}\n`;
}

function swiftTheme() {
  const rows = Object.entries(NATIVE_TOKENS).map(([name, token]) => {
    const camel = pascal(name).replace(/^./, (letter) => letter.toLowerCase());
    return `    static let ${camel} = dynamic(light: 0x${light[token].slice(1)}, dark: 0x${dark[token].slice(1)})`;
  });
  return `// ${GENERATED}
import SwiftUI
import UIKit

/// The Palee theme for the widgets: light (Frost) and dark (Graphite), like the app.
enum PaleeTheme {
${rows.join("\n")}

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
`;
}

function shellCss() {
  const block = (tokens: ThemeTokens) =>
    Object.entries(NATIVE_TOKENS)
      .map(([name, token]) => `--${name.replace(/_/g, "-")}: ${tokens[token]};`)
      .join(" ");
  return `/* ${GENERATED} */
:root { color-scheme: light dark; ${block(light)} }
@media (prefers-color-scheme: dark) { :root { ${block(dark)} } }
`;
}

function capacitorTheme() {
  return `${JSON.stringify({ _comment: GENERATED, light: { background: light.bg }, dark: { background: dark.bg } }, null, 2)}\n`;
}

/** Print colours for the API's emails, receipts and wallet passes (paper is light). */
function elixirPalette() {
  const tokens: (keyof ThemeTokens)[] = ["paper", "bg", "text", "textSoft", "muted", "border", "primary", "primaryContrast", "deep", "deepContrast"];
  const snake = (name: string) => name.replace(/([A-Z])/g, "_$1").toLowerCase();
  const rows = tokens.map((token) => `    ${snake(token)}: "${PRINT_TOKENS[token]}"`);
  return `defmodule Palee.BrandPalette do
  @moduledoc """
  The Palee colours for the emails, documents and wallet passes the API renders.

  ${GENERATED}
  """

  @colours %{
${rows.join(",\n")}
  }

  @doc "A print colour by its theme token name, e.g. \`colour(:primary)\`."
  def colour(token), do: Map.fetch!(@colours, token)
end
`;
}

/** Every generated file, by its path from the repository root. */
export function nativeThemeFiles(): Record<string, string> {
  const android = "apps/mobile/android/app/src/main/res";
  const assets = "apps/mobile/ios/App/App/Assets.xcassets";
  const colourSets = Object.fromEntries(
    Object.entries(NATIVE_TOKENS).map(([name, token]) => [`${assets}/Palee${pascal(name)}.colorset/Contents.json`, iosColourSet(token)]),
  );
  return {
    [`${android}/values/palee_theme.xml`]: androidColours(light),
    [`${android}/values-night/palee_theme.xml`]: androidColours(dark),
    [`${android}/values/ic_launcher_background.xml`]: `<?xml version="1.0" encoding="utf-8"?>\n<!-- ${GENERATED} -->\n<resources>\n    <color name="ic_launcher_background">${light.primary}</color>\n</resources>\n`,
    ...colourSets,
    [`${assets}/Splash.imageset/Contents.json`]: splashImageSet(),
    [`${assets}/Splash.imageset/splash.svg`]: splashSvg(light),
    [`${assets}/Splash.imageset/splash-dark.svg`]: splashSvg(dark),
    "apps/mobile/ios/App/PaleeWidgets/PaleeTheme.swift": swiftTheme(),
    "apps/mobile/www/palee-theme.css": shellCss(),
    "apps/mobile/palee-theme.json": capacitorTheme(),
    "apps/api/lib/palee/brand_palette.ex": elixirPalette(),
  };
}
