#!/usr/bin/env python3
"""Token-free unit tests for the narrow AI discussion relay."""

import unittest

from discussion_bridge import (
    BridgeError,
    destination,
    format_relay,
    is_relay,
    source_marker,
)


class BridgeTests(unittest.TestCase):
    def test_only_configured_issue(self):
        event = {"issue": {"number": 297}, "comment": {
            "id": 44, "body": "hello", "user": {"login": "Nolavel"}
        }}
        self.assertEqual(destination("issue_comment", event, 297, 1), "discussion")
        self.assertIsNone(destination("issue_comment", event, 1, 1))
        event["issue"]["pull_request"] = {"url": "example"}
        self.assertIsNone(destination("issue_comment", event, 297, 1))

    def test_only_configured_discussion(self):
        event = {"discussion": {"number": 1}, "comment": {
            "id": 50, "body": "hi", "user": {"login": "Nolavel"}
        }}
        self.assertEqual(destination("discussion_comment", event, 297, 1), "issue")
        event["discussion"]["number"] = 2
        self.assertIsNone(destination("discussion_comment", event, 297, 1))

    def test_no_loop_or_bot_comment(self):
        event = {"issue": {"number": 297}, "comment": {
            "id": 44, "body": "hello <!-- hoarbound-bridge:discussion:12 -->",
            "user": {"login": "Nolavel"}
        }}
        self.assertIsNone(destination("issue_comment", event, 297, 1))
        event["comment"]["body"] = "hello"
        event["comment"]["user"]["login"] = "github-actions[bot]"
        self.assertIsNone(destination("issue_comment", event, 297, 1))

    def test_attribution_and_marker(self):
        body = format_relay(
            source="issue", source_number=297, author="Nolavel",
            url="https://github.com/Nolavel/Hoarbound/issues/297#issuecomment-44",
            body="ChatGPT (GPT-6) на связи", source_id="44",
        )
        self.assertIn("ChatGPT (GPT-6) на связи", body)
        self.assertTrue(is_relay(body))
        self.assertIn(source_marker("issue", "44"), body)
        self.assertIn("GitHub author @Nolavel", body)

    def test_reject_truncation_and_bad_marker(self):
        with self.assertRaises(BridgeError):
            format_relay(
                source="discussion", source_number=1, author="X",
                url="https://example.org/", body="x" * 25001, source_id="2",
            )
        with self.assertRaises(BridgeError):
            source_marker("issue", "bad")


if __name__ == "__main__":
    unittest.main()
