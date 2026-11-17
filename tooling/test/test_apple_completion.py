"""Regression coverage for the Swift Testing terminal-summary gate."""

import unittest

from run_apple_tests import Completion


class CompletionTests(unittest.TestCase):
    def complete(self, start, summary):
        completion = Completion()
        completion.line(start)
        completion.line(summary)
        return completion

    def test_unicode_and_sf_symbols(self):
        for start, passed, spacing in [("◇", "✔", " "),
                                       ("\U001007c8", "\U0010105b", "  ")]:
            with self.subTest(start=start):
                result = self.complete(start + spacing + "Test run started.",
                    passed + spacing + "Test run with 256 tests in 34 suites passed after 16.000 seconds.")
                self.assertTrue(result.successful())

    def test_incomplete_and_empty_runs_fail(self):
        for start, summary in [("", "✔ Test run with 1 test passed after 1 second."),
                               ("◇ Test run started.", ""),
                               ("◇ Test run started.", "✔ Test run with 0 tests passed after 1 second.")]:
            self.assertFalse(self.complete(start, summary).successful())

    def test_unknown_failure_and_conflicting_terminals_fail(self):
        for summary in ["✘ Test run with 1 test failed after 1 second.",
                        "✔ Test run with 1 test failed after 1 second.",
                        "\U0010105c  Test run with 1 test failed after 1 second."]:
            result = self.complete("◇ Test run started.", summary)
            self.assertFalse(result.successful())
            result.line("✔ Test run with 1 test passed after 1 second.")
            self.assertFalse(result.successful())


if __name__ == "__main__":
    unittest.main()
