import { readdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

async function filesUnder(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(entries.map((entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? filesUnder(path) : [path];
  }));
  return nested.flat();
}

for (const path of await filesUnder(new URL("../src", import.meta.url).pathname)) {
  if (!path.endsWith(".tsx")) continue;
  let source = await readFile(path, "utf8");
  if (!source.includes("const i18n = useUiTranslations()") || !source.includes(".message")) continue;

  const migrated = source.replace(
    /\b([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*)\.message\b/g,
    "localizeError($1, i18n)",
  );
  if (migrated === source) continue;

  source = migrated;
  if (!source.includes('from "@/i18n/presentation"')) {
    const importLine = 'import { localizeError } from "@/i18n/presentation";\n';
    const marker = 'import {useUiTranslations} from "@/i18n/ui";\n';
    source = source.includes(marker) ? source.replace(marker, marker + importLine) : importLine + source;
  }
  await writeFile(path, source);
  console.log(path);
}
