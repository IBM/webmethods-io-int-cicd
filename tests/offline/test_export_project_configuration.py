from __future__ import annotations

import json
import os

from support import SCRIPTS, WorkspaceTest, run


class ExportProjectConfigurationTests(WorkspaceTest):
    def setUp(self):
        super().setUp()
        self.project = self.workspace / "sample"
        self.project.mkdir()
        self.mock_bin = self.workspace / "mock-bin"
        self.mock_bin.mkdir()
        self.write(
            "mock-bin/curl",
            """#!/bin/bash
set -e
output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cp "$WMIO_RESPONSE" "$output"
printf '%s' "$WMIO_STATUS"
""",
            executable=True,
        )

    def invoke(self, response, status):
        return run(
            [
                "bash", SCRIPTS / "exportProjectConfiguration.sh",
                "https://tenant.example", "admin", "SECRET", "sample",
                self.workspace, "NA", "debug",
            ],
            env={
                "PATH": f"{self.mock_bin}:{os.environ['PATH']}",
                "WMIO_RESPONSE": str(response),
                "WMIO_STATUS": str(status),
            },
        )

    def test_writes_valid_project_configuration(self):
        response = self.write_json(
            "valid.json",
            {
                "metadata": {"project": "project-id"},
                "configurations": {"packages": []},
                "globals": {},
            },
        )

        result = self.invoke(response, 200)

        self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        exported = self.project / "assets/projectConfigs/ProjectConfiguration/ProjectConfiguration_List_Full.json"
        self.assertEqual("project-id", json.loads(exported.read_text())["metadata"]["project"])

    def test_502_removes_invalid_artifacts_without_writing_error_body(self):
        output_dir = self.project / "assets/projectConfigs/ProjectConfiguration"
        output_dir.mkdir(parents=True)
        (output_dir / "ProjectConfiguration_List_Full.json").write_text(
            '{"code":502,"message":"old error"}\n', encoding="utf-8"
        )
        (output_dir / "configurations_packages.json").write_text("null\n", encoding="utf-8")
        response = self.write_json("error.json", {"code": 502, "message": "Bad Gateway"})

        result = self.invoke(response, 502)

        self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        self.assertIn("export skipped (HTTP 502)", result.stdout)
        self.assertFalse(output_dir.exists())

    def test_502_preserves_previous_valid_export(self):
        output_dir = self.project / "assets/projectConfigs/ProjectConfiguration"
        output_dir.mkdir(parents=True)
        previous = output_dir / "ProjectConfiguration_List_Full.json"
        previous.write_text('{"configurations":{"packages":[]}}\n', encoding="utf-8")
        response = self.write_json("error.json", {"code": 502, "message": "Bad Gateway"})

        result = self.invoke(response, 502)

        self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        self.assertTrue(previous.exists())
        self.assertEqual([], json.loads(previous.read_text())["configurations"]["packages"])
