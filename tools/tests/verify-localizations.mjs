import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { execFileSync } from "node:child_process";

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
const currentSources = swiftFiles.map(file => ({
  path: path.relative(root, file),
  source: fs.readFileSync(file, "utf8"),
}));
const missing = missingLocalizations(currentSources, catalog.strings);
const baselineMissing = baselineMissingLocalizations(process.env.REYNARD_DIFF_BASE);

for (const key of baselineMissing) {
  missing.delete(key);
}

if (missing.size > 0) {
  const details = [...missing.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, location]) => `  ${JSON.stringify(key)} (${location})`)
    .join("\n");
  throw new Error(`New localized Swift strings missing from the catalog:\n${details}`);
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

function missingLocalizations(sources, strings) {
  const result = new Map();
  for (const { path: sourcePath, source } of sources) {
    for (const match of source.matchAll(localizationPattern)) {
      const key = decodeSwiftStringLiteral(match[1]);
      if (strings[key] === undefined) {
        const line = source.slice(0, match.index).split("\n").length;
        result.set(key, `${sourcePath}:${line}`);
      }
    }
  }
  return result;
}

function baselineMissingLocalizations(revision) {
  if (!revision?.trim()) {
    return new Set();
  }

  const catalogSource = git(["show", `${revision}:${path.relative(root, catalogPath)}`]);
  const baselineCatalog = JSON.parse(catalogSource);
  const sourcePaths = git([
    "ls-tree",
    "-r",
    "--name-only",
    revision,
    "--",
    "browser/Reynard",
    "browser/GeckoView",
  ]).split("\n").filter(file => file.endsWith(".swift"));
  const sources = sourcePaths.map(sourcePath => ({
    path: sourcePath,
    source: git(["show", `${revision}:${sourcePath}`]),
  }));
  return new Set(missingLocalizations(sources, baselineCatalog.strings).keys());
}

function git(args) {
  return execFileSync("git", args, {
    cwd: root,
    encoding: "utf8",
    maxBuffer: 32 * 1024 * 1024,
  });
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
