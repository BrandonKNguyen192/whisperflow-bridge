#!/usr/bin/env python3
"""Regression tests for login-item upgrades."""

import os
import plistlib
import tempfile
import unittest
from unittest import mock

import launch


class LoginMigrationTests(unittest.TestCase):
    def test_migrates_token_from_legacy_plist(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            plist_path = os.path.join(temp_dir, "legacy.plist")
            with open(plist_path, "wb") as fh:
                plistlib.dump(
                    {"ProgramArguments": ["python3", "launch.py", "--token", "legacy-secret"]},
                    fh,
                )

            with mock.patch.object(launch, "PLIST_PATH", plist_path), mock.patch.object(
                launch.server, "persist_token"
            ) as persist_token:
                self.assertTrue(launch.migrate_legacy_login_token())
                persist_token.assert_called_once_with("legacy-secret")

    def test_ignores_plist_without_token(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            plist_path = os.path.join(temp_dir, "current.plist")
            with open(plist_path, "wb") as fh:
                plistlib.dump({"ProgramArguments": ["python3", "launch.py"]}, fh)

            with mock.patch.object(launch, "PLIST_PATH", plist_path), mock.patch.object(
                launch.server, "persist_token"
            ) as persist_token:
                self.assertFalse(launch.migrate_legacy_login_token())
                persist_token.assert_not_called()


if __name__ == "__main__":
    unittest.main()
