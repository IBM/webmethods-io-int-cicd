from __future__ import annotations

import json
import os
import shutil

from support import SCRIPTS, WorkspaceTest, run


class ExportProjectModeTests(WorkspaceTest):
    def setUp(self):
        super().setUp()
        if not shutil.which("yq"):
            self.skipTest("yq is required to exercise exportDadaMetadata.sh")
        self.project = self.workspace / "sample"
        self.project.mkdir()
        (self.project / "project-config.yml").write_text(
            "project:\n  project-id: legacy-id\n  project-name: sample\n",
            encoding="utf-8",
        )
        self.configs = self.workspace / "configs/env"
        self.configs.mkdir(parents=True)
        for environment in ("play", "dev", "qa", "prod"):
            (self.configs / f"{environment}.yml").write_text(
                f"tenant:\n  type: {environment}\n", encoding="utf-8"
            )
        self.mock_bin = self.workspace / "mock-bin"
        self.mock_bin.mkdir()
        self.write(
            "mock-bin/curl",
            """#!/bin/bash
set -e
output=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    http*) url="$1"; shift ;;
    *) shift ;;
  esac
done
if [[ "$url" == *'/configurations' ]]; then
  cp "$WMIO_CONFIG_RESPONSE" "$output"
  printf '200'
else
  printf '%s' '{"message":"Not Found"}' > "$output"
  printf '404'
fi
""",
            executable=True,
        )

    def test_export_repairs_legacy_internal_git_metadata_and_exports_packages(self):
        response = self.write_json(
            "configuration-response.json",
            {
                "metadata": {"project": "api-id"},
                "configurations": {
                    "packages": [{
                        "packageName": "SupportPkg",
                        "gitUrl": "https://git.example/scm/packages",
                        "gitServerName": "user_git",
                        "gitUserName": "developer",
                        "gitBranch": "development",
                    }]
                },
            },
        )
        result = run(
            [
                "bash", SCRIPTS / "exportDadaMetadata.sh",
                "https://tenant.example", "admin", "SECRET", "sample",
                self.project, "owner", "PAT", self.configs, "debug",
            ],
            env={
                "PATH": f"{self.mock_bin}:{os.environ['PATH']}",
                "WMIO_CONFIG_RESPONSE": str(response),
            },
        )
        self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        project_config = (self.project / "project-config.yml").read_text(encoding="utf-8")
        self.assertIn("project-id: api-id", project_config)
        self.assertIn("external-git:\n    enabled: false", project_config)
        metadata = self.project / "assets/dada/config/imported-package-metadata.yml"
        self.assertTrue(metadata.exists())
        metadata_json = json.loads(run(["yq", "-o=json", ".", metadata]).stdout)
        self.assertEqual("SupportPkg", metadata_json["packages"][0]["name"])
        mapping = self.project / "assets/dada/config/imported-package-branches.yml"
        self.assertTrue(mapping.exists())
        self.assertFalse((self.project / "assets/dada/config/scaffolding").exists())
