from __future__ import annotations

import json
import os

from support import SCRIPTS, WorkspaceTest, run


class ImportedPackageBranchTests(WorkspaceTest):
    def setUp(self):
        super().setUp()
        scaffolding = self.workspace / "sample/assets/dada/config/scaffolding"
        scaffolding.mkdir(parents=True)
        (scaffolding / "SampleProject.yml").write_text(
            """packages:
  - name: SampleProject
    gitUrl: https://github.example/owner
    gitServerName: account
    gitUsername: developer
    gitBranch: dev
  - name: SupportPkg
    gitUrl: https://github.example/owner
    gitServerName: account
    gitUsername: developer
    gitBranch: dev
""",
            encoding="utf-8",
        )
        self.mock_bin = self.workspace / "mock-bin"
        self.mock_bin.mkdir()
        curl = self.mock_bin / "curl"
        curl.write_text(
            """#!/bin/bash
set -e
payload=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --data-raw) payload="$2"; shift 2 ;;
    --output) response="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf '%s' "$payload" > "$WMIO_CURL_CAPTURE"
printf '%s' '{}' > "$response"
printf '201'
""",
            encoding="utf-8",
        )
        curl.chmod(0o755)

    def invoke(self, *extra):
        capture = self.workspace / "captured-request.json"
        result = run(
            [
                "bash", SCRIPTS / "importDadaPackages.sh",
                "https://tenant.example", "admin", "SECRET", "sample",
                self.workspace / "sample", *extra,
            ],
            env={
                "PATH": f"{self.mock_bin}:{os.environ['PATH']}",
                "WMIO_CURL_CAPTURE": str(capture),
            },
        )
        self.assertTrue(
            capture.exists(),
            f"package import did not reach curl\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}",
        )
        return result, json.loads(capture.read_text(encoding="utf-8"))

    def test_target_environment_overrides_scaffolding_branch_in_request_only(self):
        scaffolding = self.workspace / "sample/assets/dada/config/scaffolding/SampleProject.yml"
        original = scaffolding.read_text(encoding="utf-8")
        result, payload = self.invoke("qa", "debug")
        self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        self.assertEqual("qa", payload["gitBranch"])
        self.assertNotIn("scaffoldingBranch", payload)
        self.assertIn("scaffolding branch 'dev', target branch 'qa'", result.stderr)
        self.assertEqual(original, scaffolding.read_text(encoding="utf-8"))

    def test_legacy_debug_argument_preserves_scaffolding_branch(self):
        result, payload = self.invoke("debug")
        self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        self.assertEqual("dev", payload["gitBranch"])
        self.assertIn("scaffolding branch 'dev', target branch 'dev'", result.stderr)
