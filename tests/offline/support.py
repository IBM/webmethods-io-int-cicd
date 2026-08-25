"""Helpers for invoking functional scripts in isolated temporary workspaces."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / "pipelines" / "scripts"


def run(command, cwd=None, env=None, check=False):
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    return subprocess.run(
        [str(item) for item in command],
        cwd=cwd,
        env=merged_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=check,
    )


def git(cwd, *args, check=True):
    return run(["git", *args], cwd=cwd, check=check)


class WorkspaceTest(unittest.TestCase):
    def setUp(self):
        self._temporary = tempfile.TemporaryDirectory(prefix="wmio-offline-")
        self.workspace = Path(self._temporary.name)

    def tearDown(self):
        self._temporary.cleanup()

    def write(self, relative, content, executable=False):
        path = self.workspace / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        if executable:
            path.chmod(0o755)
        return path

    def write_json(self, relative, value):
        return self.write(relative, json.dumps(value, indent=2) + "\n")

