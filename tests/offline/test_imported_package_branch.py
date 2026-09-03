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

    def test_explicit_mapping_overrides_environment_name(self):
        mapping = self.workspace / "sample/assets/dada/config/imported-package-branches.yml"
        mapping.write_text(
            '''version: "1.0"
packages:
  SupportPkg:
    branches:
      qa: release/qa
''',
            encoding="utf-8",
        )
        result, payload = self.invoke("qa", "debug")
        self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        self.assertEqual("release/qa", payload["gitBranch"])

    def test_present_mapping_fails_when_target_environment_is_missing(self):
        mapping = self.workspace / "sample/assets/dada/config/imported-package-branches.yml"
        mapping.write_text(
            '''version: "1.0"
packages:
  SupportPkg:
    branches:
      dev: dev
''',
            encoding="utf-8",
        )
        capture = self.workspace / "captured-request.json"
        result = run(
            [
                "bash", SCRIPTS / "importDadaPackages.sh",
                "https://tenant.example", "admin", "SECRET", "sample",
                self.workspace / "sample", "qa", "debug",
            ],
            env={
                "PATH": f"{self.mock_bin}:{os.environ['PATH']}",
                "WMIO_CURL_CAPTURE": str(capture),
            },
        )
        self.assertNotEqual(0, result.returncode)
        self.assertFalse(capture.exists())
        self.assertIn("defines a branch for environment 'qa'", result.stderr)

    def test_mapping_generator_preserves_override_and_adds_missing_environments(self):
        config_dir = self.workspace / "configs/env"
        config_dir.mkdir(parents=True)
        (config_dir / "dev.yml").write_text("tenant:\n  type: dev\n", encoding="utf-8")
        (config_dir / "play.yml").write_text("tenant:\n  type: play\n", encoding="utf-8")
        (config_dir / "qa.yml").write_text("tenant:\n  type: qa\n", encoding="utf-8")
        mapping = self.workspace / "sample/assets/dada/config/imported-package-branches.yml"
        mapping.write_text(
            '''version: "1.0"
packages:
  SupportPkg:
    branches:
      dev: custom-development
''',
            encoding="utf-8",
        )
        result = run(
            [
                "bash", SCRIPTS / "updateImportedPackageBranchMap.sh",
                self.workspace / "sample",
                self.workspace / "sample/assets/dada/config/scaffolding/SampleProject.yml",
                config_dir,
                "debug",
            ],
        )
        self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        generated = run(["yq", "-o=json", ".", mapping])
        policy = json.loads(generated.stdout)
        branches = policy["packages"]["SupportPkg"]["branches"]
        self.assertEqual("dev", branches["play"])
        self.assertEqual("custom-development", branches["dev"])
        self.assertEqual("qa", branches["qa"])
        self.assertEqual(["play", "dev", "qa"], list(branches))

    def test_mapping_generator_refreshes_play_from_scaffolding(self):
        config_dir = self.workspace / "configs/env"
        config_dir.mkdir(parents=True)
        (config_dir / "play.yml").write_text("tenant:\n  type: play\n", encoding="utf-8")
        mapping = self.workspace / "sample/assets/dada/config/imported-package-branches.yml"
        mapping.write_text(
            '''version: "1.0"
packages:
  SupportPkg:
    branches:
      play: stale-branch
''',
            encoding="utf-8",
        )
        result = run(
            [
                "bash", SCRIPTS / "updateImportedPackageBranchMap.sh",
                self.workspace / "sample",
                self.workspace / "sample/assets/dada/config/scaffolding/SampleProject.yml",
                config_dir,
                "debug",
            ],
        )
        self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        generated = run(["yq", "-o=json", ".", mapping])
        policy = json.loads(generated.stdout)
        self.assertEqual("dev", policy["packages"]["SupportPkg"]["branches"]["play"])
