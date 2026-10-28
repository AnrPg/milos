// A difficulty level's code is the short id WOD text uses (`[scale: rx]`) and
// workout history stores. The API accepts only `a-z0-9` words joined by `-`, and
// a saved level keeps its code for good, so the settings screen derives a new
// level's code from its name instead of asking the coach for one.

const GREEK: Record<string, string> = {
  α: "a", β: "v", γ: "g", δ: "d", ε: "e", ζ: "z", η: "i", θ: "th", ι: "i", κ: "k",
  λ: "l", μ: "m", ν: "n", ξ: "x", ο: "o", π: "p", ρ: "r", σ: "s", ς: "s", τ: "t",
  υ: "y", φ: "f", χ: "ch", ψ: "ps", ω: "o",
};

const CYRILLIC: Record<string, string> = {
  а: "a", б: "b", в: "v", г: "g", д: "d", е: "e", ё: "e", ж: "zh", з: "z", и: "i",
  й: "y", к: "k", л: "l", м: "m", н: "n", о: "o", п: "p", р: "r", с: "s", т: "t",
  у: "u", ф: "f", х: "h", ц: "ts", ч: "ch", ш: "sh", щ: "sht", ъ: "a", ы: "y",
  ь: "", э: "e", ю: "yu", я: "ya",
};

export function slugifyLevelName(name: string): string {
  const latin = Array.from(
    name
      .replace(/\+/g, " plus ")
      .normalize("NFD")
      .replace(/\p{M}/gu, "")
      .toLowerCase(),
  )
    .map((char) => GREEK[char] ?? CYRILLIC[char] ?? char)
    .join("");

  return latin.replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40).replace(/-+$/g, "");
}

/** The code for a new level: from its name, unique among `taken`, `level-N` when the name has no Latin letters. */
export function newLevelCode(name: string, taken: Iterable<string>, position: number): string {
  const used = new Set(taken);
  const base = slugifyLevelName(name) || `level-${position}`;
  if (!used.has(base)) return base;
  let n = 2;
  while (used.has(`${base}-${n}`)) n += 1;
  return `${base}-${n}`;
}
