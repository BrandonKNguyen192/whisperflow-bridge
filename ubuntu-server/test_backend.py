#!/usr/bin/env python3
"""Tests for Ubuntu input backend command selection."""

import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import backend


class UbuntuBackendTests(unittest.TestCase):
    @mock.patch.object(backend.time, "sleep")
    @mock.patch.object(backend.subprocess, "run")
    def test_x11_types_with_clipboard_and_xdotool(self, run, _sleep):
        with mock.patch.dict(backend.os.environ, {"XDG_SESSION_TYPE": "x11", "DISPLAY": ":0"}, clear=True):
            self.assertTrue(backend.type_text("hello", "type"))

        self.assertEqual(["xclip", "-selection", "clipboard"], run.call_args_list[0].args[0])
        self.assertEqual(
            ["xdotool", "key", "--clearmodifiers", "ctrl+v"],
            run.call_args_list[1].args[0],
        )

    @mock.patch.object(backend.shutil, "which", side_effect=lambda name: f"/usr/bin/{name}")
    @mock.patch.object(backend.subprocess, "run")
    def test_wayland_enter_uses_ydotool(self, run, _which):
        with mock.patch.dict(backend.os.environ, {"XDG_SESSION_TYPE": "wayland"}, clear=True):
            self.assertTrue(backend.type_text("", "enter"))

        run.assert_called_once_with(
            ["ydotool", "key", "28:1", "28:0"],
            check=True,
        )

    @mock.patch.object(backend.shutil, "which", return_value=None)
    def test_missing_wayland_tools_are_reported(self, _which):
        with mock.patch.dict(backend.os.environ, {"XDG_SESSION_TYPE": "wayland"}, clear=True):
            with self.assertRaisesRegex(RuntimeError, "wl-clipboard"):
                backend.ensure_ready()


if __name__ == "__main__":
    unittest.main()
