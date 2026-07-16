import { readFile, writeFile } from "node:fs/promises";

const path = new URL("../lib/milos_training_web/controllers/fallback_controller.ex", import.meta.url).pathname;
let source = await readFile(path, "utf8");

source = source.replace(
  /(def call\(conn, \{:error, (?::|\{\:)([a-z0-9_]+)[\s\S]*?\n  end)/g,
  (block, _whole, code) => {
    if (/\bcode:/.test(block)) return block;
    return block.replace(/json\(%\{error:/, `json(%{code: "${code}", error:`);
  },
);

source = source
  .replace(
    "json(%{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)})",
    'json(%{code: "validation_failed", errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)})',
  )
  .replace(
    "json(%{errors: normalized_errors})",
    'json(%{code: "validation_failed", errors: normalized_errors})',
  );

await writeFile(path, source);
