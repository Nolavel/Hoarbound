"""Unit checks for check_dynamic_dispatch.py: counting, comments, and the ratchet's three outcomes."""
import unittest

import check_dynamic_dispatch as ratchet


class CountTest(unittest.TestCase):
    def test_counts_both_forms_and_ignores_comments(self):
        text = 'if a.has_method(&"x"):\n\ta.call(&"x")\n\tb.call("y", 1)\n# a.has_method(&"z")\nvar c = d.callv(m, [])\n'
        self.assertEqual(ratchet.count(text), 3)


class CompareTest(unittest.TestCase):
    def test_equal_passes(self):
        self.assertEqual(ratchet.compare({"a.gd": 2}, {"a.gd": 2}), [])

    def test_growth_new_file_drop_and_gone_all_fail(self):
        problems = ratchet.compare({"a.gd": 3, "new.gd": 1, "b.gd": 1}, {"a.gd": 2, "b.gd": 2, "gone.gd": 1})
        text = "\n".join(problems)
        self.assertIn("a.gd: 3 dynamic calls, baseline 2", text)
        self.assertIn("new.gd: 1 new dynamic call", text)
        self.assertIn("b.gd: 1 dynamic calls, baseline 2; lower its line", text)
        self.assertIn("gone.gd: no dynamic calls left", text)


if __name__ == "__main__":
    unittest.main()
