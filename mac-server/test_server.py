#!/usr/bin/env python3
"""Regression tests for the Whisper Bridge HTTP protocol."""

import http.client
import json
import threading
import unittest
from unittest import mock

import server


class BridgeProtocolTests(unittest.TestCase):
    def setUp(self):
        server.AUTH_TOKEN = "test-token"
        server.ALLOWED_HOSTS = {"127.0.0.1"}
        self.httpd = server.BridgeServer(("127.0.0.1", 0), server.BridgeHandler)
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join(timeout=2)

    def post(self, payload):
        conn = http.client.HTTPConnection("127.0.0.1", self.httpd.server_port, timeout=2)
        conn.request(
            "POST",
            "/send",
            body=json.dumps(payload),
            headers={
                "Authorization": "Bearer test-token",
                "Content-Type": "application/json",
            },
        )
        response = conn.getresponse()
        body = json.loads(response.read())
        conn.close()
        return response.status, body

    @mock.patch.object(server, "chime")
    @mock.patch.object(server, "notify")
    @mock.patch.object(server, "type_text", return_value=True)
    def test_enter_accepts_empty_text(self, type_text, _notify, _chime):
        status, body = self.post({"text": "", "mode": "enter", "source": "test"})

        self.assertEqual(200, status)
        self.assertTrue(body["ok"])
        self.assertEqual("enter", body["mode"])
        type_text.assert_called_once_with("", "enter", enter_after=False)

    @mock.patch.object(server, "type_text")
    def test_type_rejects_empty_text(self, type_text):
        status, body = self.post({"text": "", "mode": "type"})

        self.assertEqual(400, status)
        self.assertEqual("empty text", body["error"])
        type_text.assert_not_called()

    def test_rejects_non_string_text(self):
        status, body = self.post({"text": ["not", "text"], "mode": "type"})

        self.assertEqual(400, status)
        self.assertEqual("text must be a string", body["error"])


class AllowedHostTests(unittest.TestCase):
    @mock.patch.object(server.socket, "gethostname", return_value="Studio")
    @mock.patch.object(server, "get_tail_ip", return_value="100.64.1.2")
    @mock.patch.object(server, "get_lan_ip", return_value="192.168.1.2")
    def test_configures_hosts_for_all_entry_points(self, _lan, _tail, _hostname):
        server.configure_allowed_hosts(["studio.example.ts.net"])

        self.assertIn("localhost", server.ALLOWED_HOSTS)
        self.assertIn("studio.local", server.ALLOWED_HOSTS)
        self.assertIn("192.168.1.2", server.ALLOWED_HOSTS)
        self.assertIn("100.64.1.2", server.ALLOWED_HOSTS)
        self.assertIn("studio.example.ts.net", server.ALLOWED_HOSTS)


if __name__ == "__main__":
    unittest.main()
