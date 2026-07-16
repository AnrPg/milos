import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import ts from "typescript";

const sourceRoot = path.resolve("src");
const englishCatalogPath = path.resolve("messages/en.json");
const translatedAttributes = new Set(["alt", "aria-description", "aria-label", "aria-placeholder", "label", "placeholder", "title"]);
const translatedProperties = new Set(["actionLabel", "ariaLabel", "description", "emptyLabel", "errorMessage", "eyebrow", "helperText", "label", "message", "placeholder", "subtitle", "title"]);
const translatedCalls = new Set(["alert", "confirm", "prompt", "setError", "setMessage"]);
const ignoredDirectories = new Set(["api", "types"]);

function sourceFiles(directory) {
  return fs.readdirSync(directory, {withFileTypes: true}).flatMap((entry) => {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) return ignoredDirectories.has(entry.name) ? [] : sourceFiles(fullPath);
    return entry.isFile() && fullPath.endsWith(".tsx") && !fullPath.includes(".test.") ? [fullPath] : [];
  });
}

function normalize(raw) {
  return raw
    .replace(/&amp;/g, "&")
    .replace(/&apos;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/\s+/g, " ")
    .trim();
}

function hasWords(value) {
  return /\p{L}/u.test(value);
}

function isStyleText(node) {
  let current = node.parent;
  while (current) {
    if (ts.isJsxElement(current) && current.openingElement.tagName.getText() === "style") return true;
    current = current.parent;
  }
  return false;
}

function functionName(node) {
  if (ts.isFunctionDeclaration(node)) return node.name?.text ?? (node.modifiers?.some((item) => item.kind === ts.SyntaxKind.DefaultKeyword) ? "DefaultExport" : null);
  if ((ts.isArrowFunction(node) || ts.isFunctionExpression(node)) && ts.isVariableDeclaration(node.parent) && ts.isIdentifier(node.parent.name)) return node.parent.name.text;
  return null;
}

function ownerFunction(node) {
  let current = node.parent;
  while (current) {
    if (ts.isFunctionDeclaration(current) || ts.isArrowFunction(current) || ts.isFunctionExpression(current)) {
      const name = functionName(current);
      if (name && (/^[A-Z]/.test(name) || /^use[A-Z]/.test(name))) return current;
    }
    current = current.parent;
  }
  return null;
}

const technicalProperties = new Set([
  "accept", "action", "accent", "apple", "background", "border", "borderBottom", "borderLeft",
  "className", "color", "currency", "event", "format", "href", "icon", "id", "inputType", "kind",
  "manifest", "method", "name", "pattern", "rel", "role", "scope", "slug", "source", "status",
  "target", "type", "unit", "value", "variant", "style", "accept", "content", "localeMatcher",
  "dateStyle", "timeStyle", "day", "month", "year", "hour", "minute", "second", "weekday",
  "borderLeft", "borderRight", "borderTop", "borderBottom", "borderColor", "borderRadius", "padding",
  "margin", "backgroundSize", "backgroundImage", "maxWidth", "minWidth", "width", "height",
]);
const technicalCalls = new Set([
  "endsWith", "get", "getItem", "getPropertyValue", "includes", "join", "localeCompare", "querySelector",
  "removeItem", "replace", "replaceAll", "set", "setItem", "setProperty", "slice", "split", "startsWith",
  "substring", "useTranslations", "open", "addEventListener", "removeEventListener",
]);

function isTechnicalValue(value) {
  const trimmed = value.trim();
  return /^(?:use client|https?:|\/|\.\/|\.\.\/|@\/)/.test(trimmed)
    || /^(?:var|rgb|rgba|hsl|color-mix|linear-gradient|conic-gradient|calc)\(/.test(trimmed)
    || /(?:^|\s)(?:\d+(?:\.\d+)?(?:px|rem|em|vh|vw)|solid var\(|transparent)(?:\s|$)/.test(trimmed)
    || /^[a-z]{2}(?:-[A-Z]{2})?$/.test(trimmed)
    || /^[\w.+-]+\/[\w.+-]+$/.test(trimmed)
    || /\.(?:svg|ics|json|webmanifest)$/.test(trimmed)
    || /^(?:GET|POST|PATCH|PUT|DELETE|Escape|Enter|Tab|Arrow\w+)$/.test(trimmed);
}

function looksGeneralUi(value) {
  const trimmed = value.trim();
  return /\s/u.test(trimmed) || /^[A-Z+←·⚠✓✕]/u.test(trimmed) || /[…!?]$/u.test(trimmed);
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

function slug(value) {
  const words = value
    .normalize("NFKD")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .split(/\s+/)
    .slice(0, 8);
  const base = words
    .map((word, index) => index === 0 ? word.toLowerCase() : word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
    .join("")
    .replace(/^\d/, "message$&") || "message";
  return `${base}${crypto.createHash("sha1").update(value).digest("hex").slice(0, 7)}`;
}

function literalValue(node) {
  return ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node) ? node.text : null;
}

const catalog = JSON.parse(fs.readFileSync(englishCatalogPath, "utf8"));
catalog.Ui ??= {};
const keyByMessage = new Map(Object.entries(catalog.Ui).map(([key, message]) => [message, key]));
const unresolved = [];
let replacementCount = 0;

function messageKey(message) {
  if (keyByMessage.has(message)) return keyByMessage.get(message);
  let key = slug(message);
  let suffix = 2;
  while (Object.hasOwn(catalog.Ui, key) && catalog.Ui[key] !== message) key = `${slug(message)}${suffix++}`;
  catalog.Ui[key] = message;
  keyByMessage.set(message, key);
  return key;
}

for (const filename of sourceFiles(sourceRoot)) {
  let source = fs.readFileSync(filename, "utf8");
  const sourceFile = ts.createSourceFile(filename, source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
  const replacements = [];
  const owners = new Set();
  const handledNodes = new Set();

  function add(node, rawValue, render) {
    if (handledNodes.has(node)) return;
    const message = normalize(rawValue);
    if (!hasWords(message) || isStyleText(node)) return;
    const owner = ownerFunction(node);
    if (!owner || !owner.body || !ts.isBlock(owner.body)) {
      const {line} = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile));
      unresolved.push(`${path.relative(process.cwd(), filename)}:${line + 1} ${JSON.stringify(message)}`);
      return;
    }
    handledNodes.add(node);
    const key = messageKey(message);
    replacements.push({start: node.getStart(sourceFile), end: node.getEnd(), text: render(key, node)});
    owners.add(owner);
    replacementCount += 1;
  }

  function visit(node) {
    if (ts.isJsxText(node)) {
      const raw = node.getText(sourceFile);
      add(node, raw, (key) => {
        const leading = raw.match(/^\s*/)?.[0] ?? "";
        const trailing = raw.match(/\s*$/)?.[0] ?? "";
        return `${leading}{i18n(${JSON.stringify(key)})}${trailing}`;
      });
    }
    if (ts.isJsxAttribute(node) && translatedAttributes.has(node.name.getText(sourceFile))) {
      if (node.initializer && ts.isStringLiteral(node.initializer)) add(node.initializer, node.initializer.text, (key) => `{i18n(${JSON.stringify(key)})}`);
      else if (node.initializer && ts.isJsxExpression(node.initializer) && node.initializer.expression) {
        const value = literalValue(node.initializer.expression);
        if (value !== null) add(node.initializer.expression, value, (key) => `i18n(${JSON.stringify(key)})`);
      }
    }
    if (ts.isJsxExpression(node) && node.expression) {
      const value = literalValue(node.expression);
      if (value !== null) add(node.expression, value, (key) => `i18n(${JSON.stringify(key)})`);
    }
    if (ts.isPropertyAssignment(node)) {
      const keyName = node.name.getText(sourceFile).replace(/^['"]|['"]$/g, "");
      if (translatedProperties.has(keyName)) {
        const value = literalValue(node.initializer);
        if (value !== null) add(node.initializer, value, (key) => `i18n(${JSON.stringify(key)})`);
      }
    }
    if (ts.isCallExpression(node)) {
      const callee = node.expression.getText(sourceFile).split(".").at(-1);
      if (translatedCalls.has(callee)) {
        for (const argument of node.arguments) {
          const value = literalValue(argument);
          if (value !== null) add(argument, value, (key) => `i18n(${JSON.stringify(key)})`);
        }
      }
    }

    if ((ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) && !handledNodes.has(node)) {
      const value = node.text;
      if (looksGeneralUi(value) && !isTechnicalValue(value) && !isTechnicalContext(node, sourceFile)) {
        const isAttribute = ts.isJsxAttribute(node.parent);
        add(node, value, (key) => isAttribute ? `{i18n(${JSON.stringify(key)})}` : `i18n(${JSON.stringify(key)})`);
      }
    }

    if (ts.isTemplateExpression(node) && !isTechnicalContext(node, sourceFile) && !isStyleText(node)) {
      const pieces = [node.head.text, ...node.templateSpans.map((span) => span.literal.text)];
      const message = normalize(pieces.map((piece, index) => index < node.templateSpans.length ? `${piece}{value${index}}` : piece).join(""));
      if (hasWords(message) && looksGeneralUi(message) && !isTechnicalValue(message)) {
        const owner = ownerFunction(node);
        if (owner && owner.body && ts.isBlock(owner.body)) {
          const key = messageKey(message);
          const values = node.templateSpans.map((span, index) => `value${index}: ${span.expression.getText(sourceFile)}`).join(", ");
          replacements.push({start: node.getStart(sourceFile), end: node.getEnd(), text: `i18n(${JSON.stringify(key)}, {${values}})`});
          owners.add(owner);
          replacementCount += 1;
          return;
        }
      }
    }
    ts.forEachChild(node, visit);
  }
  visit(sourceFile);

  for (const owner of owners) {
    if (owner.body.getText(sourceFile).includes("const i18n =")) continue;
    const isAsync = owner.modifiers?.some((modifier) => modifier.kind === ts.SyntaxKind.AsyncKeyword);
    const helper = isAsync ? "getUiTranslations" : "useUiTranslations";
    replacements.push({start: owner.body.getStart(sourceFile) + 1, end: owner.body.getStart(sourceFile) + 1, text: `\n  const i18n = ${isAsync ? "await " : ""}${helper}();`});
  }

  if (replacements.length === 0) continue;
  const needsServerHelper = [...owners].some((owner) => owner.modifiers?.some((modifier) => modifier.kind === ts.SyntaxKind.AsyncKeyword));
  const needsHook = [...owners].some((owner) => !owner.modifiers?.some((modifier) => modifier.kind === ts.SyntaxKind.AsyncKeyword));
  const importText = `${needsHook && !source.includes('from "@/i18n/ui"') ? 'import {useUiTranslations} from "@/i18n/ui";\n' : ""}${needsServerHelper && !source.includes('from "@/i18n/ui-server"') ? 'import {getUiTranslations} from "@/i18n/ui-server";\n' : ""}`;
  const directive = source.match(/^(["']use client["'];?\s*)/);
  replacements.push({start: directive ? directive[0].length : 0, end: directive ? directive[0].length : 0, text: `\n${importText}`});

  for (const replacement of replacements.sort((a, b) => b.start - a.start)) {
    source = source.slice(0, replacement.start) + replacement.text + source.slice(replacement.end);
  }
  fs.writeFileSync(filename, source);
}

fs.writeFileSync(englishCatalogPath, `${JSON.stringify(catalog, null, 2)}\n`);
console.log(`Migrated ${replacementCount} UI-copy occurrences into ${Object.keys(catalog.Ui).length} catalog messages.`);
if (unresolved.length > 0) {
  console.error(`Unresolved module-level or expression-bodied copy (${unresolved.length}):\n${unresolved.join("\n")}`);
  process.exitCode = 2;
}
