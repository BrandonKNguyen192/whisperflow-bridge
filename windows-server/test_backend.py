#!/usr/bin/env python3
"""Tests for the Windows in-process SendInput backend."""

import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import backend


class WindowsBackendTests(unittest.TestCase):
    def test_type_writes_clipboard_and_pastes(self):
        with mock.patch.object(backend, "_clipboard_write", return_value=True) as write, \
             mock.patch.object(backend, "_send_key") as send_key, \
             mock.patch.object(backend.time, "sleep"):
            self.assertTrue(backend.type_text("hello", "type"))
            write.assert_called_once_with("hello")
            keys = [c.kwargs["vk"] for c in send_key.call_args_list]
            # Ctrl down, V down, V up, Ctrl up
            self.assertEqual([backend.VK_CONTROL, 0x56, 0x56, backend.VK_CONTROL], keys)

    def test_enter_presses_return(self):
        with mock.patch.object(backend, "_send_key") as send_key:
            self.assertTrue(backend.type_text("", "enter"))
            calls = send_key.call_args_list
            self.assertEqual(backend.VK_RETURN, calls[0].kwargs["vk"])
            self.assertEqual(backend.KEYEVENTF_KEYUP, calls[1].kwargs.get("flags", 0))

    def test_clipboard_mode_writes_clipboard(self):
        with mock.patch.object(backend, "_clipboard_write") as write:
            self.assertTrue(backend.type_text("hello", "clipboard"))
            write.assert_called_once_with("hello")

    def test_append_reads_then_writes(self):
        with mock.patch.object(backend, "_clipboard_write") as write, \
             mock.patch.object(backend, "_clipboard_read", return_value="old"):
            self.assertTrue(backend.type_text("new", "append"))
            write.assert_called_once_with("old\r\nnew")

    def test_type_unicode_handles_surrogate_pairs(self):
        with mock.patch.object(backend, "_send_key") as send_key:
            backend._type_unicode("\U0001F600")  # 😀 → D83D DE00
            self.assertEqual([0xD83D, 0xD83D, 0xDE00, 0xDE00],
                             [c.kwargs["scan"] for c in send_key.call_args_list])

    def test_enter_after_type(self):
        with mock.patch.object(backend, "_clipboard_write", return_value=True) as write, \
             mock.patch.object(backend, "_send_key") as send_key, \
             mock.patch.object(backend.time, "sleep"):
            backend.type_text("x", "type", enter_after=True)
            self.assertTrue(write.called)
            last = send_key.call_args_list[-1]
            self.assertEqual(backend.VK_RETURN, last.kwargs["vk"])

    def test_mouse_scroll_wheel_delta(self):
        with mock.patch.object(backend, "_send_mouse") as send_mouse:
            ok, _ = backend.control_mouse("scroll", dy=-90)
            self.assertTrue(ok)
            self.assertEqual((-90 * 4) & 0xFFFFFFFF, send_mouse.call_args.kwargs["data"])

    def test_mouse_click_sequence(self):
        with mock.patch.object(backend, "_send_mouse") as send_mouse:
            ok, _ = backend.control_mouse("click", button="right")
            self.assertTrue(ok)
            self.assertEqual(
                [backend.MOUSEEVENTF_RIGHTDOWN, backend.MOUSEEVENTF_RIGHTUP],
                [c.args[0] for c in send_mouse.call_args_list],
            )

    def test_clipboard_roundtrip(self):
        self.assertTrue(backend._clipboard_write("roundtrip-42"))
        self.assertEqual("roundtrip-42", backend._clipboard_read())

    def test_no_powershell_dependency(self):
        self.assertNotIn("powershell", backend.describe().lower())
        backend.ensure_ready()  # must not raise


if __name__ == "__main__":
    unittest.main()
