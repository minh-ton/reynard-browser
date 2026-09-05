"""Regression tests for structural and format checks in Xcode string catalogs."""

import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from check_catalogs import validate_catalog


def unit(value, state="translated"):
    return {"stringUnit": {"state": state, "value": value}}


def plural(**values):
    return {"variations": {"plural": {name: unit(value) for name, value in values.items()}}}


def catalog(source, target, *, source_language="en", key=None):
    return {
        "sourceLanguage": source_language,
        "strings": {
            source if key is None else key: {
                "localizations": {source_language: unit(source), "zh-Hans": target}
            }
        },
        "version": "1.0",
    }


class CatalogTests(unittest.TestCase):
    def errors(self, data):
        return [
            diagnostic
            for diagnostic in validate_catalog(data, file="Example.xcstrings")
            if diagnostic.severity == "error"
        ]

    def test_valid_plain_translation(self):
        self.assertEqual([], self.errors(catalog("Settings", unit("设置"))))

    def test_percent_in_prose_warns_instead_of_blocking(self):
        for source, target in (("100% complete", "完成 100%"),
                               ("All done", "100% complete"),
                               ("50% off", "半价"), ("100% sure", "完全确定")):
            with self.subTest(source=source, target=target):
                diagnostics = validate_catalog(catalog(source, unit(target)))
                self.assertFalse(any(d.severity == "error" for d in diagnostics))
                self.assertTrue(any(d.code == "ambiguous-percent" for d in diagnostics))
        self.assertEqual([], validate_catalog(catalog("100%% complete", unit("已完成 100%%"))))

    def test_space_flag_with_a_real_argument_still_validates(self):
        self.assertEqual([], self.errors(catalog("Value: % d", unit("值：%1$d"))))
        self.assertTrue(self.errors(catalog("Value: % d", unit("值：%@"))))

    def test_explicit_empty_source_or_plural_leaf_is_not_silent(self):
        data = catalog("Open %@", unit("打开"))
        for source in ({}, {"variations": {"plural": {"one": {}}}}):
            with self.subTest(source=source):
                data["strings"]["Open %@"]["localizations"]["en"] = source
                self.assertTrue(self.errors(data))

    def test_missing_language_is_allowed(self):
        data = {"sourceLanguage": "en", "strings": {"Settings": {}}, "version": "1.0"}
        self.assertEqual([], self.errors(data))

    def test_unfinished_targets_are_allowed(self):
        for state in ("new", "needs_translation"):
            with self.subTest(state=state):
                self.assertEqual([], self.errors(catalog("Open %@", unit("", state))))

    def test_empty_completed_target_warns_without_blocking_missing_translation(self):
        for value in ("", "   "):
            with self.subTest(value=value):
                diagnostics = validate_catalog(catalog("Settings", unit(value)))
                self.assertFalse(any(d.severity == "error" for d in diagnostics))
                self.assertTrue(any(d.severity == "warning" for d in diagnostics))

    def test_empty_source_and_target_are_allowed(self):
        self.assertEqual([], self.errors(catalog("", unit(""))))

    def test_missing_format_argument_is_an_error(self):
        for source, target in (("Open %@", "打开"), ("%d tabs", "标签页")):
            with self.subTest(source=source):
                errors = self.errors(catalog(source, unit(target)))
                self.assertTrue(errors)
                self.assertTrue(any(d.key == source and d.locale == "zh-Hans" for d in errors))
                self.assertTrue(all(isinstance(d.code, str) and d.code for d in errors))

    def test_extra_format_argument_is_an_error(self):
        self.assertTrue(self.errors(catalog("Settings", unit("设置 %@"))))

    def test_changed_format_type_is_an_error(self):
        self.assertTrue(self.errors(catalog("%d tabs", unit("%@ 个标签页"))))

    def test_unpositioned_argument_type_swap_is_an_error(self):
        self.assertTrue(self.errors(catalog("%@ has %d tabs", unit("%d 有 %@ 个标签页"))))

    def test_positioned_arguments_can_be_reordered(self):
        for source in ("%@ has %d tabs", "%1$@ has %2$d tabs"):
            with self.subTest(source=source):
                self.assertEqual([], self.errors(catalog(source, unit("%2$d 个标签页属于 %1$@"))))

    def test_positioned_argument_type_swap_is_an_error(self):
        self.assertTrue(self.errors(catalog("%1$@ has %2$d tabs", unit("%1$d 个标签页属于 %2$@"))))

    def test_positioned_argument_can_be_reused(self):
        self.assertEqual([], self.errors(catalog("Allow %@ access", unit("允许 %1$@ 访问，以便使用 %1$@"))))

    def test_dynamic_width_and_precision_preserve_argument_indexes(self):
        self.assertEqual([], self.errors(catalog("Value: %*.*f", unit("数值：%3$*1$.*2$f"))))
        self.assertTrue(self.errors(catalog("Value: %*.*f", unit("数值：%f"))))

    def test_invalid_length_modifier_is_rejected(self):
        self.assertTrue(self.errors(catalog("Value: %f", unit("值：%llf"))))
        self.assertEqual([], self.errors(catalog("Value: %lld", unit("值：%qd"))))

    def test_literal_percent_is_not_a_format_argument(self):
        self.assertEqual([], self.errors(catalog("Use %%s for a literal", unit("字面文本写作 %%s"))))
        self.assertTrue(self.errors(catalog("Use %%s for a literal", unit("字面文本写作 %s"))))

    def test_mixed_argument_indexes_and_dangling_percent_are_errors(self):
        for source, target in (
            ("%@ has %d tabs", "%@ 有 %2$d 个标签页"),
            ("%d domains", "%d 个域名%"),
        ):
            with self.subTest(target=target):
                self.assertTrue(self.errors(catalog(source, unit(target))))

    def test_source_language_and_value_take_precedence_over_key(self):
        data = catalog("%d onglets", unit("%d 个标签页"), source_language="fr", key="tab_count")
        data["strings"]["tab_count"]["localizations"]["en"] = unit("%d tabs")
        self.assertEqual([], self.errors(data))
        data["strings"]["tab_count"]["localizations"]["zh-Hans"] = unit("%@ 个标签页")
        self.assertTrue(self.errors(data))

    def test_key_is_source_when_source_localization_is_absent(self):
        data = catalog("Open %@", unit("打开 %@"))
        del data["strings"]["Open %@"]["localizations"]["en"]
        self.assertEqual([], self.errors(data))
        data["strings"]["Open %@"]["localizations"]["zh-Hans"] = unit("打开")
        self.assertTrue(self.errors(data))

    def test_nontranslatable_entry_skips_target_format_checks(self):
        data = catalog("Open %@", unit("打开"))
        data["strings"]["Open %@"]["shouldTranslate"] = False
        self.assertEqual([], self.errors(data))

    def test_plural_categories_can_differ_between_languages(self):
        data = catalog("%d tabs", plural(other="%d 个标签页"))
        data["strings"]["%d tabs"]["localizations"]["en"] = plural(one="%d tab", other="%d tabs")
        data["strings"]["%d tabs"]["localizations"]["ru"] = plural(
            one="%d вкладка", few="%d вкладки", many="%d вкладок", other="%d вкладки"
        )
        self.assertEqual([], self.errors(data))

    def test_plural_format_type_change_is_an_error(self):
        data = catalog("%d tabs", plural(other="%@ 个标签页"))
        data["strings"]["%d tabs"]["localizations"]["en"] = plural(one="%d tab", other="%d tabs")
        self.assertTrue(self.errors(data))

    def test_fixed_plural_count_can_be_spelled_out(self):
        data = catalog("%d tabs", plural(one="一个标签页", other="%d 个标签页"))
        data["strings"]["%d tabs"]["localizations"]["en"] = plural(one="%d tab", other="%d tabs")
        diagnostics = validate_catalog(data)
        self.assertFalse(any(d.severity == "error" for d in diagnostics))
        self.assertTrue(any(d.code == "plural-count" for d in diagnostics))

    def test_device_variants_use_matching_source_and_fallback(self):
        data = catalog("open", {"variations": {"device": {
            "ipad": unit("打开 %d 个标签页"), "iphone": unit("打开 %@")}}})
        data["strings"]["open"]["localizations"]["en"] = {"variations": {"device": {
            "ipad": unit("Open %d tabs"), "other": unit("Open %@")}}}
        self.assertEqual([], self.errors(data))
        data["strings"]["open"]["localizations"]["zh-Hans"]["variations"]["device"]["ipad"] = unit("打开 %@")
        self.assertTrue(self.errors(data))

    def test_unsupported_substitutions_are_reported_not_certified(self):
        data = catalog("%d tabs", {"substitutions": {"count": {"argNum": 1}}})
        diagnostics = validate_catalog(data)
        self.assertFalse(any(d.severity == "error" for d in diagnostics))
        self.assertTrue(any(d.code == "unsupported-substitutions" for d in diagnostics))

    def test_nested_variants_prefer_specific_device_before_plural_fallback(self):
        data = catalog("item", {"variations": {"device": {
            "ipad": plural(one="项目 %@")}}})
        data["strings"]["item"]["localizations"]["en"] = {"variations": {"device": {
            "other": plural(one="%d item", other="%d items"),
            "ipad": plural(other="Item %@")}}}
        self.assertEqual([], self.errors(data))

    def test_malformed_catalog_structure_is_an_error(self):
        for data in (
            [],
            {"sourceLanguage": "en", "strings": []},
            {"sourceLanguage": "en", "strings": {"Settings": {"localizations": []}}},
            catalog("Settings", unit(42)),
        ):
            with self.subTest(data=data):
                self.assertTrue(self.errors(data))


class CommandLineTests(unittest.TestCase):
    script = Path(__file__).resolve().with_name("check_catalogs.py")

    def run_checker(self, directory, *arguments):
        return subprocess.run(
            [sys.executable, str(self.script), *map(str, arguments)],
            cwd=directory,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )

    def write_catalog(self, path, source="Open %@", target="打开 %@"):
        path.write_text(json.dumps(catalog(source, unit(target)), ensure_ascii=False), encoding="utf-8")

    def commit_baseline(self, directory, filename):
        for arguments in (
            ["init", "-q"],
            ["add", filename],
            ["-c", "user.name=Catalog Tests", "-c", "user.email=tests@example.invalid",
             "-c", "commit.gpgsign=false", "commit", "-qm", "Baseline"],
        ):
            subprocess.run(["git", *arguments], cwd=directory, check=True, capture_output=True)

    def test_valid_file_and_machine_readable_output(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Valid.xcstrings"
            self.write_catalog(path)
            result = self.run_checker(directory, "--json", path)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertIsInstance(json.loads(result.stdout), dict)

    def test_invalid_json_reports_file_without_traceback(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Broken.xcstrings"
            path.write_text('{"strings": ', encoding="utf-8")
            result = self.run_checker(directory, path)
            self.assertNotEqual(0, result.returncode)
            self.assertIn(path.name, result.stdout + result.stderr)
            self.assertNotIn("Traceback", result.stdout + result.stderr)

    def test_duplicate_keys_and_nonstandard_json_constants_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Broken.xcstrings"
            for value in ('{"sourceLanguage":"en","sourceLanguage":"fr","strings":{}}',
                          '{"sourceLanguage":"en","strings":{},"version":NaN}'):
                with self.subTest(value=value):
                    path.write_text(value, encoding="utf-8")
                    result = self.run_checker(directory, path)
                    self.assertEqual(1, result.returncode)
                    self.assertNotIn("Traceback", result.stdout + result.stderr)

    def test_missing_path_is_a_usage_error(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_checker(directory, Path(directory) / "missing.xcstrings")
            self.assertEqual(2, result.returncode)

    def test_directory_scan_finds_error_in_nested_catalog(self):
        with tempfile.TemporaryDirectory() as directory:
            nested = Path(directory) / "Resources"
            nested.mkdir()
            self.write_catalog(nested / "Broken.xcstrings", target="打开")
            result = self.run_checker(directory, directory)
            self.assertNotEqual(0, result.returncode)
            self.assertIn("Broken.xcstrings", result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which("git"), "git is required for baseline integration testing")
    def test_baseline_allows_old_error_but_rejects_changed_bad_translation(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Localizable.xcstrings"
            self.write_catalog(path, target="打开")
            self.commit_baseline(directory, path.name)
            unchanged = self.run_checker(directory, "--base", "HEAD", path)
            self.assertEqual(0, unchanged.returncode, unchanged.stdout + unchanged.stderr)
            self.write_catalog(path, target="开启")
            changed = self.run_checker(directory, "--base", "HEAD", path)
            self.assertNotEqual(0, changed.returncode)
            self.assertIn(path.name, changed.stdout + changed.stderr)

    @unittest.skipUnless(shutil.which("git"), "git is required for baseline integration testing")
    def test_unreadable_utf8_baseline_reports_an_error_without_traceback(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Localizable.xcstrings"
            path.write_bytes(b'{"sourceLanguage":"en","strings":{},"comment":"\xff"}')
            self.commit_baseline(directory, path.name)
            self.write_catalog(path)
            result = self.run_checker(directory, "--base", "HEAD", path)
            self.assertEqual(2, result.returncode, result.stdout + result.stderr)
            self.assertIn(path.name, result.stderr)
            self.assertNotIn("Traceback", result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which("git"), "git is required for baseline integration testing")
    def test_new_catalog_is_checked_and_bad_base_is_not_ignored(self):
        with tempfile.TemporaryDirectory() as directory:
            seed = Path(directory) / "Seed.xcstrings"
            self.write_catalog(seed)
            self.commit_baseline(directory, seed.name)
            new = Path(directory) / "New.xcstrings"
            self.write_catalog(new, target="打开")
            result = self.run_checker(directory, "--base", "HEAD", new)
            self.assertEqual(1, result.returncode, result.stdout + result.stderr)
            self.assertIn(new.name, result.stdout)
            self.write_catalog(new)
            result = self.run_checker(directory, "--base", "HEAD", new)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            result = self.run_checker(directory, "--base", "does-not-exist", new)
            self.assertEqual(2, result.returncode, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
