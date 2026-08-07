#!/usr/bin/env python3
"""Compatibility entry point for the shared Whisper Bridge server."""

import os
import sys

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT_DIR)

from common.bridge_server import *  # noqa: F401,F403,E402
from common import bridge_server  # noqa: E402


if __name__ == "__main__":
    bridge_server.main()
