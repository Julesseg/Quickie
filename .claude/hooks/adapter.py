#!/usr/bin/env python3
"""Forward Claude hook payloads to the shared agent hook dispatcher."""

import os
from pathlib import Path
import sys


root = Path(os.environ.get("CLAUDE_PROJECT_DIR", Path.cwd())).resolve()
dispatcher = root / ".agents" / "hooks" / "dispatch.py"
os.execv(sys.executable, [sys.executable, str(dispatcher), *sys.argv[1:]])
