import fs from "node:fs";
import path from "node:path";
import ts from "typescript";

function files(directory) {
  return fs.readdirSync(directory, {withFileTypes: true}).flatMap((entry) => {
    const filename = path.join(directory, entry.name);
    return entry.isDirectory() ? files(filename) : entry.isFile() && filename.endsWith(".tsx") ? [filename] : [];
  });
}

function declaresI18n(functionNode) {
  if (!functionNode.body || !ts.isBlock(functionNode.body)) return false;
  return functionNode.body.statements.some((statement) =>
    ts.isVariableStatement(statement)
    && statement.declarationList.declarations.some((declaration) => ts.isIdentifier(declaration.name) && declaration.name.text === "i18n"),
  );
}

let removed = 0;
for (const filename of files(path.resolve("src"))) {
  let source = fs.readFileSync(filename, "utf8");
  const originalSource = source;
  const sourceFile = ts.createSourceFile(filename, source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
  const removals = [];

  function inspect(node) {
    if (ts.isFunctionLike(node) && declaresI18n(node)) {
      const declaration = node.body.statements.find((statement) =>
        ts.isVariableStatement(statement)
        && statement.declarationList.declarations.some((item) => ts.isIdentifier(item.name) && item.name.text === "i18n"),
      );
      let references = 0;
      function count(current) {
        if (current !== node && ts.isFunctionLike(current) && declaresI18n(current)) return;
        if (ts.isIdentifier(current) && current.text === "i18n" && current !== declaration.declarationList.declarations[0].name) references += 1;
        ts.forEachChild(current, count);
      }
      count(node.body);
      if (references === 0) {
        let start = declaration.getFullStart();
        const end = declaration.getEnd();
        if (/^\s*$/.test(source.slice(start, declaration.getStart(sourceFile)))) start = declaration.getStart(sourceFile);
        removals.push({start, end});
      }
    }
    ts.forEachChild(node, inspect);
  }
  inspect(sourceFile);

  for (const removal of removals.sort((a, b) => b.start - a.start)) {
    source = source.slice(0, removal.start) + source.slice(removal.end);
    removed += 1;
  }
  if (!source.includes("useUiTranslations()")) {
    source = source.replace(/^import \{useUiTranslations\} from "@\/i18n\/ui";\s*\n?/m, "");
  }
  if (!source.includes("getUiTranslations()")) {
    source = source.replace(/^import \{getUiTranslations\} from "@\/i18n\/ui-server";\s*\n?/m, "");
  }
  if (source !== originalSource) fs.writeFileSync(filename, source);
}

console.log(`Removed ${removed} unused localization hooks.`);
