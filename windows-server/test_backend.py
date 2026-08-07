#!/usr/bin/env python3
"""Tests for Windows input backend command construction."""

import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import backend


class WindowsBackendTests(unittest.TestCase):
    @mock.patch.object(backend.time, "sleep")
    @mock.patch.object(backend, "_powershell")
    def test_type_writes_clipboard_then_pastes(self, powershell, _sleep):
        self.assertTrue(backend.type_text("hello", "type"))

        self.assertEqual("hello", powershell.call_args_list[0].args[1])
        self.assertIn("SendWait('^v')", powershell.call_args_list[1].args[0])

    @mock.patch.object(backend, "_powershell")
    def test_enter_uses_sendkeys(self, powershell):
        self.assertTrue(backend.type_text("", "enter"))
        self.assertIn("SendWait('{ENTER}')", powershell.call_args.args[0])


if __name__ == "__main__":
    unittest.main()
