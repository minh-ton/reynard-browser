# String catalog checks

Run from the repository root with Python 3.11 or newer. No packages, Xcode, or
Gecko build are required. The checker reads files; it does not edit translations.

```sh
python -B tools/localization/check_catalogs.py
python -B tools/localization/check_catalogs.py browser/Reynard/Resources/Localizable.xcstrings
python -B tools/localization/check_catalogs.py --base origin/main
python -B tools/localization/check_catalogs.py --json
python -B -m unittest discover -s tools/localization -v
```

Without paths, all `.xcstrings` files under `browser/` are checked. Explicit paths
may name files or directories. An invalid path or a directory containing no
catalogs is an error rather than a successful empty scan.

## What is checked

- JSON syntax (including duplicate keys) and the structure of existing string
  units and variants.
- The types and positions of printf arguments in translations, including `%@`,
  `%d`, `%ld`, `%lld`, `%f`, dynamic width/precision, and numbered arguments.
- Added or missing arguments and malformed formats in formatted strings.
- Source text comes from `sourceLanguage`, not necessarily English. The catalog
  key is used only when the source localization is absent.

Numbered arguments can be reordered or reused: `%@ has %d tabs` and
`%2$d tabs belong to %1$@` have the same argument contract. Replacing `%1$@` with
`%1$d` does not. `%%` prints a literal percent; the `s` in `%%s` is not an argument.
Formatting flags and decimal precision may differ without changing argument
types. Device/plural variants use their matching source variant, falling back
to `other` when needed.

Some percent signs are ambiguous without inspecting the Swift caller. For
example, `100% complete` looks like a space-flagged `%c` conversion followed by
`omplete`. Those cases warn and skip argument comparison, rather than rejecting
ordinary prose. A genuine space-flagged conversion such as `% d` is checked.

## Avoiding translation false positives

Missing languages and untranslated entries are allowed. `new` and
`needs_translation` string units are skipped. Empty `needs_review` units are
allowed; an empty unit marked `translated` or `final` is a warning for manual
review, not a blocking error. `shouldTranslate: false` entries still receive
structural validation, but no target-format checks.

Languages may use different plural categories. The checker does not require the
same categories as the source. A `zero`, `one`, or `two` form may spell out its
single numeric selector; an omitted count in those forms is a warning. It cannot
decide whether the wording is grammatically correct for a language.

Named `substitutions` and unfamiliar variation axes are reported as warnings,
with format checking skipped for that localization. They are not silently
certified as valid. This tool is not an Xcode compiler or a complete catalog
schema validator. It does not judge translation meaning, terminology, layout,
newline choices, or whether a Swift localization call uses the correct table.

## Existing errors and CI

A full scan reports all current issues and exits with status `1` if any error is
found. Warnings do not make the check fail. Command-line/configuration errors
exit with status `2`; success exits with status `0`.

`--base REF` compares diagnostics with catalogs at a Git revision, without
changing the working tree. A diagnostic is ignored only when its location,
message, source text, target text, and target state are unchanged. Editing an
already broken translation without fixing its format makes it reportable again.
A new file is fully checked. Missing/unreadable Git baselines fail explicitly.

The workflow runs tests on Windows and Linux. Pull requests use the base commit
to check regressions, so legacy issues do not block unrelated translation work.
A manually dispatched run performs a full audit and may fail on existing issues.

The source-key coverage check proposed separately in PR #214 serves a different
purpose: it checks Swift references and selected source strings. This checker
validates the translated values in all three catalogs and can run alongside it.

Format reference: [Apple's NSString format specifiers](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Strings/Articles/formatSpecifiers.html).
