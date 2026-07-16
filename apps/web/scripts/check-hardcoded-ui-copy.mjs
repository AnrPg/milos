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
]);
const technicalProperties = new Set([
  "accept", "action", "accent", "apple", "background", "border", "borderBottom", "borderLeft",
  "borderRight", "borderTop", "borderColor", "borderRadius", "className", "color", "content",
  "currency", "dateStyle", "day", "event", "format", "height", "hour", "href", "icon", "id",
  "inputType", "kind", "localeMatcher", "manifest", "margin", "method", "minute", "month", "name",
  "padding", "pattern", "rel", "role", "scope", "second", "slug", "source", "status", "style",
  "target", "timeStyle", "type", "unit", "value", "variant", "weekday", "width", "year",
]);
const technicalCalls = new Set([
  "addEventListener", "endsWith", "get", "getItem", "getPropertyValue", "includes", "join",
  "localeCompare", "open", "querySelector", "removeEventListener", "removeItem", "replace", "replaceAll",
  "set", "setItem", "setProperty", "slice", "split", "startsWith", "substring", "useTranslations",
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

function looksLikeDisplayCopy(value) {
  const trimmed = value.trim();
  return /\s/u.test(trimmed) || /^[A-Z+←·⚠✓✕]/u.test(trimmed) || /[…!?]$/u.test(trimmed);
}

function location(sourceFile, node) {
  const {line, character} = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile));
  return `${path.relative(process.cwd(), sourceFile.fileName)}:${line + 1}:${character + 1}`;
}

function literalValue(node) {
  if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) return node.text;
  return null;
}

function isTechnicalValue(value) {
  const trimmed = value.trim();
  return /^(?:use client|https?:|\/|\.\/|\.\.\/|@\/)/.test(trimmed)
    || /^(?:var|rgb|rgba|hsl|color-mix|linear-gradient|conic-gradient|calc)\(/.test(trimmed)
    || /(?:^|\s)(?:\d+(?:\.\d+)?(?:px|rem|em|vh|vw)|solid var\(|transparent)(?:\s|$)/.test(trimmed)
    || /^[a-z]{2}(?:-[A-Z]{2})?$/.test(trimmed)
    || /^[A-Z]{3}$/.test(trimmed)
    || /^T\d{2}:\d{2}:\d{2}$/.test(trimmed)
    || /^@keyframes\b/.test(trimmed)
    || /^\(\(\)\s*=>\s*\{/.test(trimmed)
    || /^\([\w-]+\s*:/.test(trimmed)
    || /^[\w.+-]+\/[\w.+-]+$/.test(trimmed)
    || /\.(?:svg|ics|json|webmanifest)$/.test(trimmed)
    || /^(?:GET|POST|PATCH|PUT|DELETE|Escape|Enter|Tab|Arrow\w+)$/.test(trimmed);
}

function isTechnicalContext(node, sourceFile) {
  let current = node.parent;
  while (current && !ts.isFunctionLike(current)) {
    if (ts.isImportDeclaration(current) || ts.isExportDeclaration(current) || ts.isLiteralTypeNode(current)) return true;
    if (ts.isBinaryExpression(current) && [
      ts.SyntaxKind.EqualsEqualsEqualsToken,
      ts.SyntaxKind.ExclamationEqualsEqualsToken,
      ts.SyntaxKind.EqualsEqualsToken,
      ts.SyntaxKind.ExclamationEqualsToken,
    ].includes(current.operatorToken.kind)) return true;
    if (ts.isCaseClause(current) && current.expression === node) return true;
    if (ts.isJsxAttribute(current)) {
      const key = current.name.getText(sourceFile);
      if (technicalProperties.has(key) || key.startsWith("data-")) return true;
    }
    if (ts.isPropertyAssignment(current)) {
      if (current.name === node) return true;
      const key = current.name.getText(sourceFile).replace(/^['"]|['"]$/g, "");
      if (technicalProperties.has(key)) return true;
    }
    if (ts.isCallExpression(current)) {
      const callee = current.expression.getText(sourceFile).split(".").at(-1);
      if (technicalCalls.has(callee) || callee === "i18n" || callee === "t") return true;
    }
    if (ts.isNewExpression(current) && /Intl\.(?:NumberFormat|DateTimeFormat|ListFormat|RelativeTimeFormat)/.test(current.expression.getText(sourceFile))) return true;
    current = current.parent;
  }
  return false;
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
  const reportedNodes = new Set();

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
    if (hasWords(normalized)) {
      reportedNodes.add(node);
      failures.push(`${location(sourceFile, node)} ${kind}: ${JSON.stringify(normalized)}`);
    }
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

    if (
      (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node))
      && !reportedNodes.has(node)
      && hasWords(node.text)
      && looksLikeDisplayCopy(node.text)
      && !isStyleText(node)
      && !isTechnicalValue(node.text)
      && !isTechnicalContext(node, sourceFile)
    ) {
      report(node, node.text, "display literal");
    }

    if (ts.isTemplateExpression(node) && !isStyleText(node) && !isTechnicalContext(node, sourceFile)) {
      const value = [node.head.text, ...node.templateSpans.map((span) => span.literal.text)].join(" ");
      if (hasWords(value) && looksLikeDisplayCopy(value) && !isTechnicalValue(value)) report(node, value, "display template");
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
