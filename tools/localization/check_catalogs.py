#!/usr/bin/env python3
"""Check string catalog structure and printf arguments without building the app."""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import asdict, dataclass, field
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
PENDING_STATES = {"new", "needs_translation"}
FORMAT = re.compile(
    r"%(?:(?P<position>[1-9][0-9]*)\$)?(?P<flags>[-+#0 ']*)"
    r"(?P<width>[0-9]+|\*(?:[1-9][0-9]*\$)?)?"
    r"(?P<precision>\.(?:[0-9]+|\*(?:[1-9][0-9]*\$)?))?"
    r"(?P<length>hh|ll|[hlLjztq])?(?P<conversion>[@diuoxXfFeEgGaAcCsSpnDUO])"
)


@dataclass(frozen=True)
class Diagnostic:
    file: str
    key: str
    locale: str
    code: str
    message: str
    severity: str = "error"
    variant: str = ""
    fingerprint: str = field(default="", repr=False)


@dataclass
class FormatArguments:
    arguments: dict[int, str]
    errors: list[str]
    escapes: int = 0
    ambiguous: bool = False


def format_arguments(text: str) -> FormatArguments:
    """Map argument positions to types; repeated numbered references are legal."""
    arguments: dict[int, str] = {}
    errors: list[str] = []
    modes: set[bool] = set()
    next_position = 1
    escapes = 0
    ambiguous = False

    def add(position: str | None, kind: str) -> None:
        nonlocal next_position
        modes.add(position is not None)
        index = int(position) if position else next_position
        if not position:
            next_position += 1
        if index in arguments and arguments[index] != kind:
            errors.append(f"argument {index} is used as both {arguments[index]} and {kind}")
        arguments[index] = kind

    offset = 0
    while offset < len(text):
        offset = text.find("%", offset)
        if offset < 0:
            break
        if text.startswith("%%", offset):
            escapes += 1
            offset += 2
            continue
        match = FORMAT.match(text, offset)
        if not match:
            errors.append(f"unrecognized or incomplete format at character {offset + 1}")
            offset += 1
            continue
        # "% complete" can be either ordinary prose or a space-flagged %c
        # followed by "omplete". A catalog alone cannot identify the caller.
        if (" " in match["flags"] and match.end() < len(text)
                and text[match.end()].isascii() and text[match.end()].isalpha()):
            ambiguous = True
        for name in ("width", "precision"):
            value = (match[name] or "").lstrip(".")
            if value.startswith("*"):
                add(value[1:-1] if value.endswith("$") else None, "int")
        length = match["length"] or ""
        length = "ll" if length == "q" else length
        conversion = match["conversion"]
        allowed_lengths = ({"", "h", "hh", "l", "ll", "j", "z", "t"}
                           if conversion in "diuoxXn" else
                           {"", "l", "L"} if conversion in "fFeEgGaA" else
                           {"", "l"} if conversion in "cs" else {""})
        if length not in allowed_lengths:
            errors.append(f"invalid length modifier in {match[0]}")
        if conversion in "diD":
            kind = f"{length}int"
        elif conversion in "uoxXUO":
            kind = f"{length}unsigned"
        elif conversion in "fFeEgGaA":
            kind = "long double" if length == "L" else "double"
        else:
            kind = {"@": "object", "c": "char", "C": "unichar", "s": "cstring",
                    "S": "utf16string", "p": "pointer", "n": "count-pointer"}[conversion]
            if length:
                kind = length + kind
        add(match["position"], kind)
        offset = match.end()
    if len(modes) > 1:
        errors.append("numbered and unnumbered arguments are mixed")
    return FormatArguments(arguments, errors, escapes, ambiguous)


def _fingerprint(*values: object) -> str:
    text = json.dumps(values, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def validate_catalog(data: object, file: str = "<memory>") -> list[Diagnostic]:
    diagnostics: list[Diagnostic] = []

    def emit(key: str, locale: str, code: str, message: str, *, severity: str = "error",
             variant: str = "", context: object = None) -> None:
        diagnostics.append(Diagnostic(file, key, locale, code, message, severity,
                                      variant, _fingerprint(context)))

    if not isinstance(data, dict):
        emit("", "", "structure", "catalog must be an object", context=data)
        return diagnostics
    source_language = data.get("sourceLanguage")
    if not isinstance(source_language, str) or not source_language:
        emit("", "", "structure", "sourceLanguage must be a nonempty string", context=source_language)
        return diagnostics
    strings = data.get("strings")
    if not isinstance(strings, dict):
        emit("", "", "structure", "strings must be an object", context=strings)
        return diagnostics

    for key, entry in strings.items():
        if not isinstance(entry, dict):
            emit(key, "", "structure", "string entry must be an object", context=entry)
            continue
        localizations = entry.get("localizations", {})
        if not isinstance(localizations, dict):
            emit(key, "", "structure", "localizations must be an object", context=localizations)
            continue
        leaves: dict[str, list[tuple[tuple[tuple[str, str], ...], dict]]] = {}
        unsupported: set[str] = set()

        def visit(node: object, locale: str, route: tuple[tuple[str, str], ...] = ()) -> None:
            label = "/".join(f"{axis}/{category}" for axis, category in route)
            if not isinstance(node, dict):
                emit(key, locale, "structure", "localization variant must be an object",
                     variant=label, context=node)
                return
            if not any(name in node for name in ("stringUnit", "variations", "substitutions")):
                emit(key, locale, "structure", "localization or variant has no string unit or variations",
                     variant=label, context=node)
                return
            if "substitutions" in node:
                unsupported.add(locale)
                emit(key, locale, "unsupported-substitutions",
                     "named substitutions require manual checking; format validation skipped",
                     severity="warning", variant=label, context=node)
                return
            if "stringUnit" in node:
                unit = node["stringUnit"]
                if not isinstance(unit, dict) or not isinstance(unit.get("value"), str):
                    emit(key, locale, "structure", "stringUnit.value must be a string",
                         variant=label, context=unit)
                elif not isinstance(unit.get("state"), str):
                    emit(key, locale, "structure", "stringUnit.state must be a string",
                         variant=label, context=unit)
                else:
                    leaves[locale].append((route, unit))
            if "variations" in node:
                variations = node["variations"]
                if not isinstance(variations, dict) or not variations:
                    emit(key, locale, "structure", "variations must be a nonempty object",
                         variant=label, context=variations)
                    return
                for axis, choices in variations.items():
                    if not isinstance(choices, dict) or not choices:
                        emit(key, locale, "structure", "variation choices must be a nonempty object",
                             variant=label + "/" + axis, context=choices)
                        continue
                    if axis not in {"plural", "device"}:
                        unsupported.add(locale)
                        emit(key, locale, "unsupported-variation", f"unsupported variation axis: {axis}",
                             severity="warning", variant=label, context=choices)
                    for category, choice in choices.items():
                        visit(choice, locale, route + ((axis, category),))

        for locale, node in localizations.items():
            leaves[locale] = []
            visit(node, locale)
        if entry.get("shouldTranslate") is False:
            continue
        if source_language in unsupported:
            continue
        source_leaves = leaves.get(source_language, [])
        if source_language in localizations and not source_leaves:
            # A malformed/unsupported explicit source is not the same as an absent source.
            continue
        if not source_leaves:
            source_leaves = [((), {"value": key, "state": "translated"})]

        def source_for(route: tuple[tuple[str, str], ...]) -> str | None:
            candidates = []
            target_route = dict(route)
            for source_route, unit in source_leaves:
                score = []
                for axis, category in source_route:
                    if target_route.get(axis) == category:
                        score.append(2)
                    elif category == "other":
                        score.append(1)
                    else:
                        break
                else:
                    candidates.append((tuple(score), unit["value"]))
            if not candidates:
                return None
            return max(candidates, key=lambda pair: pair[0])[1]

        for locale, units in leaves.items():
            if locale == source_language or locale in unsupported:
                continue
            for route, unit in units:
                if unit["state"] in PENDING_STATES:
                    continue
                source = source_for(route)
                variant = "/".join(f"{axis}/{category}" for axis, category in route)
                context = (source, unit)
                if source is None:
                    emit(key, locale, "source-variant", "no matching source variant; review manually",
                         severity="warning", variant=variant, context=(source_leaves, unit))
                    continue
                target = unit["value"]
                if not target.strip():
                    if source.strip() and unit["state"] in {"translated", "final"}:
                        emit(key, locale, "empty-translation", "completed translation is empty; review manually",
                             severity="warning", variant=variant, context=context)
                    continue
                expected = format_arguments(source)
                actual = format_arguments(target)
                if expected.ambiguous or actual.ambiguous:
                    emit(key, locale, "ambiguous-percent",
                         "percent followed by a word may be prose rather than a format; review manually",
                         severity="warning", variant=variant, context=context)
                    continue
                active_format = bool(expected.arguments or expected.escapes)
                if expected.errors and active_format:
                    emit(key, source_language, "source-format", "; ".join(expected.errors),
                         variant=variant, context=source)
                    continue
                if actual.errors and (active_format or actual.arguments):
                    emit(key, locale, "format-syntax", "; ".join(actual.errors),
                         variant=variant, context=context)
                    continue
                missing = expected.arguments.keys() - actual.arguments.keys()
                extra = actual.arguments.keys() - expected.arguments.keys()
                wrong = {i for i in expected.arguments.keys() & actual.arguments.keys()
                         if expected.arguments[i] != actual.arguments[i]}
                # A fixed-count plural may spell out its selector ("one tab", "no tabs").
                numeric = {i for i, kind in expected.arguments.items() if kind.endswith(("int", "unsigned"))}
                fixed_plural = dict(route).get("plural") in {"zero", "one", "two"}
                if missing and not extra and not wrong and fixed_plural and missing == numeric and len(numeric) == 1:
                    emit(key, locale, "plural-count", "plural count is not printed; review wording manually",
                         severity="warning", variant=variant, context=context)
                elif missing or extra or wrong:
                    emit(key, locale, "format-arguments",
                         f"expected arguments {expected.arguments}, found {actual.arguments}",
                         variant=variant, context=context)
                if active_format and expected.escapes != actual.escapes:
                    emit(key, locale, "literal-percent", "escaped percent count differs; review literal text",
                         severity="warning", variant=variant, context=context)
    return list(dict.fromkeys(diagnostics))


def load_catalog(text: str, file: str) -> tuple[object | None, list[Diagnostic]]:
    def pairs(items: list[tuple[str, object]]) -> dict:
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key!r}")
            result[key] = value
        return result

    def invalid_constant(value: str) -> None:
        raise ValueError(f"invalid JSON constant: {value}")

    try:
        data = json.loads(text.lstrip("\ufeff"), object_pairs_hook=pairs,
                          parse_constant=invalid_constant)
    except (ValueError, RecursionError) as error:
        return None, [Diagnostic(file, "", "", "json", str(error), fingerprint=_fingerprint(text))]
    return data, validate_catalog(data, file)


def git(root: Path, *args: str) -> subprocess.CompletedProcess:
    # Decode after communicate() so invalid bytes raise in this thread. On Windows,
    # text-mode subprocess readers can fail in a background thread and return None.
    result = subprocess.run(["git", "-C", str(root), *args], capture_output=True, check=False)
    return subprocess.CompletedProcess(result.args, result.returncode,
                                       result.stdout.decode("utf-8"), result.stderr.decode("utf-8"))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path, help="catalog files or directories (default: browser/)")
    parser.add_argument("--base", help="report only diagnostics introduced or changed since this Git revision")
    parser.add_argument("--json", action="store_true", help="print a machine-readable report")
    args = parser.parse_args(argv)
    paths: set[Path] = set()
    for path in args.paths or [ROOT / "browser"]:
        if path.is_dir():
            paths.update(p.resolve() for p in path.rglob("*.xcstrings") if p.is_file())
        elif path.is_file() and path.suffix == ".xcstrings":
            paths.add(path.resolve())
        else:
            parser.error(f"not a catalog file or directory: {path}")
    if not paths:
        parser.error("no .xcstrings files found")
    base = None
    repository = ROOT
    if args.base:
        try:
            result = git(Path.cwd(), "rev-parse", "--show-toplevel")
            if result.returncode:
                parser.error("--base requires a Git working tree")
            repository = Path(result.stdout.strip()).resolve()
            result = git(repository, "rev-parse", "--verify", "--end-of-options", args.base + "^{commit}")
            if result.returncode:
                parser.error(f"cannot resolve Git baseline: {args.base}")
            base = result.stdout.strip()
        except (OSError, UnicodeError) as error:
            parser.error(str(error))

    diagnostics = []
    baseline_count = 0
    keys = 0
    for path in sorted(paths):
        try:
            relative = path.relative_to(repository)
        except ValueError:
            if base:
                parser.error(f"catalog is outside the Git working tree: {path}")
            relative = path
        label = relative.as_posix()
        try:
            data, current = load_catalog(path.read_text(encoding="utf-8-sig"), label)
        except (OSError, UnicodeError) as error:
            data, current = None, [Diagnostic(label, "", "", "read", str(error))]
        if isinstance(data, dict) and isinstance(data.get("strings"), dict):
            keys += len(data["strings"])
        if base:
            try:
                previous = git(repository, "show", f"{base}:{relative.as_posix()}")
                if previous.returncode == 0:
                    _, old = load_catalog(previous.stdout, label)
                    known = set(old)
                    baseline_count += sum(item in known for item in current)
                    current = [item for item in current if item not in known]
                else:
                    # Missing at the baseline is expected for a newly added catalog; other
                    # Git failures must not silently become a successful baseline check.
                    exists = git(repository, "ls-tree", base, "--", relative.as_posix())
                    if exists.returncode or exists.stdout.strip():
                        parser.error(f"could not read baseline catalog: {label}")
            except (OSError, UnicodeError) as error:
                parser.error(f"could not read baseline catalog {label}: {error}")
        diagnostics.extend(current)
    counts = Counter(item.severity for item in diagnostics)
    summary = {"catalogs": len(paths), "keys": keys, "errors": counts["error"],
               "warnings": counts["warning"], "baseline_diagnostics": baseline_count}
    if args.json:
        output = [{key: value for key, value in asdict(item).items() if key != "fingerprint"}
                  for item in diagnostics]
        print(json.dumps({"summary": summary, "diagnostics": output}, ensure_ascii=True, indent=2))
    else:
        for item in diagnostics:
            key = json.dumps(item.key, ensure_ascii=True)
            print(f"{item.file}: {item.severity} [{item.code}] {item.locale} {key} {item.variant}: {item.message}")
        print(f"Checked {len(paths)} catalog(s), {keys} keys: {counts['error']} error(s), "
              f"{counts['warning']} warning(s); {baseline_count} unchanged baseline diagnostic(s).")
    return 1 if counts["error"] else 0


if __name__ == "__main__":
    sys.exit(main())
