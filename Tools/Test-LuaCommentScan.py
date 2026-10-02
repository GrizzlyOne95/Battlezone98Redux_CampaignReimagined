"""Regression checks for source-port cut-code comments; run from repo root."""
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import re
import unittest

spec = spec_from_file_location(
    "campaign_validator", Path(__file__).with_name("Validate-CampaignRepository.py")
)
validator = module_from_spec(spec)
spec.loader.exec_module(validator)


class LuaCommentScanTests(unittest.TestCase):
    def test_all_long_delimiters_hide_native_cut_code(self):
        for marks in ("", "=", "==", "===="):
            with self.subTest(marks=marks):
                text = "--[" + marks + "[\n// goto is disabled C++\n" \
                    + "]" + marks + "]\nlocal active = true"
                code = validator.strip_lua_comments(text)
                self.assertNotRegex(code, r"\bgoto\b")
                self.assertIn("local active = true", code)

    def test_only_matching_delimiter_closes_comment(self):
        code = validator.strip_lua_comments(
            "--[==[\n]]\n]=]\ngoto cut\n]==]\ngoto active"
        )
        self.assertEqual(re.findall(r"\bgoto\b", code), ["goto"])
        self.assertIn("goto active", code)

    def test_executable_constructs_after_comment_remain_visible(self):
        code = validator.strip_lua_comments("--[=[cut goto]=]\ngoto active\n::label::")
        self.assertRegex(code, r"\bgoto\b")
        self.assertIn("::label::", code)

    def test_line_comments_still_hide_cut_code(self):
        code = validator.strip_lua_comments("-- goto cut\nlocal active = 1 -- goto cut\n")
        self.assertNotRegex(code, r"\bgoto\b")
        self.assertIn("local active = 1", code)

    def test_misn07_archived_comment_is_not_a_goto_statement(self):
        root = Path(__file__).resolve().parents[1]
        code = validator.strip_lua_comments((root / "Scripts/misn07.lua").read_text())
        self.assertNotRegex(code, r"\bgoto\b")

    def test_misn12_cut_blocks_are_not_executable(self):
        root = Path(__file__).resolve().parents[1]
        code = validator.strip_lua_comments((root / "Scripts/misn12.lua").read_text())
        self.assertNotIn("GameObjectHandle::", code)
        self.assertNotRegex(code, r"\bgoto\b")
        self.assertIn("function Update(dt)", code)


if __name__ == "__main__":
    unittest.main()
