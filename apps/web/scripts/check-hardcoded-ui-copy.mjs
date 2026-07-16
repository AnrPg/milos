import fs from "node:fs";
import path from "node:path";
import ts from "typescript";

const sourceRoot = path.resolve("src");
const ignoredDirectories = new Set(["api", "types"]);
const translatedAttributes = new Set([
  "alt",
  "aria-description",
  "aria-label",
  "aria-placeholder",
  "label",
  "placeholder",
  "title",
]);
const translatedProperties = new Set([
  "actionLabel",
  "ariaLabel",
  "description",
  "emptyLabel",
  "errorMessage",
  "eyebrow",
  "helperText",
  "label",
  "message",
  "placeholder",
  "subtitle",
  "title",
]);
const translatedCalls = new Set([
  "alert",
  "confirm",
  "prompt",
  "setError",
  "setMessage",
  "setStatus",
]);

function sourceFiles(directory) {
  return fs.readdirSync(directory, {withFileTypes: true}).flatMap((entry) => {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      if (ignoredDirectories.has(entry.name)) return [];
      return sourceFiles(fullPath);
    }
    return entry.isFile() && fullPath.endsWith(".tsx") && !fullPath.includes(".test.") ? [fullPath] : [];
  });
}

function hasWords(value) {
  return /\p{L}/u.test(value);
}

function location(sourceFile, node) {
  const {line, character} = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile));
  return `${path.relative(process.cwd(), sourceFile.fileName)}:${line + 1}:${character + 1}`;
}

function literalValue(node) {
  if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) return node.text;
  return null;
}

function isStyleText(node) {
  let current = node.parent;
  while (current) {
    if (ts.isJsxElement(current) && current.openingElement.tagName.getText() === "style") return true;
    current = current.parent;
  }
  return false;
}

const failures = [];

for (const filename of sourceFiles(sourceRoot)) {
  const source = fs.readFileSync(filename, "utf8");
  const sourceFile = ts.createSourceFile(filename, source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);

  function report(node, value, kind) {
    if (isStyleText(node)) return;
    const normalized = value
      .replace(/&amp;/g, "&")
      .replace(/&apos;/g, "'")
      .replace(/&quot;/g, '"')
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/\s+/g, " ")
      .trim();
    if (hasWords(normalized)) failures.push(`${location(sourceFile, node)} ${kind}: ${JSON.stringify(normalized)}`);
  }

  function visit(node) {
    if (ts.isJsxText(node)) report(node, node.getText(sourceFile), "JSX text");

    if (ts.isJsxAttribute(node) && translatedAttributes.has(node.name.getText(sourceFile))) {
      if (node.initializer && ts.isStringLiteral(node.initializer)) {
        report(node.initializer, node.initializer.text, `attribute ${node.name.getText(sourceFile)}`);
      } else if (node.initializer && ts.isJsxExpression(node.initializer) && node.initializer.expression) {
        const value = literalValue(node.initializer.expression);
        if (value !== null) report(node.initializer.expression, value, `attribute ${node.name.getText(sourceFile)}`);
      }
    }

    if (ts.isJsxExpression(node) && node.expression) {
      const value = literalValue(node.expression);
      if (value !== null) report(node.expression, value, "JSX expression");
    }

    if (ts.isPropertyAssignment(node)) {
      const key = node.name.getText(sourceFile).replace(/^['"]|['"]$/g, "");
      if (translatedProperties.has(key)) {
        const value = literalValue(node.initializer);
        if (value !== null) report(node.initializer, value, `property ${key}`);
      }
    }

    if (ts.isCallExpression(node)) {
      const callee = node.expression.getText(sourceFile).split(".").at(-1);
      if (translatedCalls.has(callee)) {
        for (const argument of node.arguments) {
          const value = literalValue(argument);
          if (value !== null) report(argument, value, `call ${callee}`);
        }
      }
    }

    ts.forEachChild(node, visit);
  }

  visit(sourceFile);
}

if (failures.length > 0) {
  console.error("Hard-coded user-interface copy found:\n");
  console.error(failures.join("\n"));
  process.exit(1);
}

console.log("No hard-coded user-interface copy found in TSX sources.");
