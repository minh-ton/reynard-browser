import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const catalogPath = path.join(root, "browser/Reynard/Resources/Localizable.xcstrings");
const catalog = JSON.parse(fs.readFileSync(catalogPath, "utf8"));

if (catalog.sourceLanguage !== "en" || typeof catalog.strings !== "object") {
  throw new Error("Localizable.xcstrings is not a valid English string catalog");
}

const sourceRoots = [
  path.join(root, "browser/Reynard"),
  path.join(root, "browser/GeckoView"),
];
const swiftFiles = sourceRoots.flatMap(filesRecursively).filter(file => file.endsWith(".swift"));
const localizationPattern = /NSLocalizedString\(\s*"((?:\\.|[^"\\])*)"/g;
const missing = new Map();

for (const file of swiftFiles) {
  const source = fs.readFileSync(file, "utf8");
  for (const match of source.matchAll(localizationPattern)) {
    const key = decodeSwiftStringLiteral(match[1]);
    if (catalog.strings[key] === undefined) {
      const relativePath = path.relative(root, file);
      const line = source.slice(0, match.index).split("\n").length;
      missing.set(key, `${relativePath}:${line}`);
    }
  }
}

if (missing.size > 0) {
  const details = [...missing.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, location]) => `  ${JSON.stringify(key)} (${location})`)
    .join("\n");
  throw new Error(`Localized Swift strings missing from the catalog:\n${details}`);
}

for (const key of ["%lld add-ons updated.", "%lld updates failed."]) {
  const plural = catalog.strings[key]?.localizations?.en?.variations?.plural;
  if (!plural?.one?.stringUnit?.value || !plural?.other?.stringUnit?.value) {
    throw new Error(`Missing English singular or plural variation for ${JSON.stringify(key)}`);
  }
}

for (const key of [
  "Cancel",
  "Capture",
  "Redraw",
  "Drag to select an area",
  "Drag a region, then extend with the blue handle",
]) {
  if (catalog.strings[key] === undefined) {
    throw new Error(`Missing FullPage Capture localization: ${JSON.stringify(key)}`);
  }
}

console.log(`Localization verification passed (${swiftFiles.length} Swift files)`);

function filesRecursively(directory) {
  const results = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      results.push(...filesRecursively(entryPath));
    } else if (entry.isFile()) {
      results.push(entryPath);
    }
  }
  return results;
}

function decodeSwiftStringLiteral(value) {
  return value.replace(/\\u\{([0-9a-fA-F]+)\}/g, (_, codePoint) =>
    String.fromCodePoint(Number.parseInt(codePoint, 16))
  ).replace(/\\([\\"nrt0])/g, (_, escape) => {
    switch (escape) {
      case "\\": return "\\";
      case "\"": return "\"";
      case "n": return "\n";
      case "r": return "\r";
      case "t": return "\t";
      case "0": return "\0";
      default: return escape;
    }
  });
}
