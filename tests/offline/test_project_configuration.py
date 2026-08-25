from __future__ import annotations

import json
import os

from support import SCRIPTS, WorkspaceTest, run


class ProjectConfigurationImportTests(WorkspaceTest):
    def invoke(self, project="sample", trace="debug"):
        mock_bin = self.workspace / "mock-bin"
        capture = self.workspace / "captured-request.json"
        mock_bin.mkdir(exist_ok=True)
        curl = mock_bin / "curl"
        curl.write_text(
            """#!/bin/bash
set -e
capture="$WMIO_CURL_CAPTURE"
payload=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --data-raw) payload="$2"; shift 2 ;;
    http*) url="$1"; shift ;;
    *) shift ;;
  esac
done
jq -n --arg url "$url" --argjson payload "$payload" '{url: $url, payload: $payload}' > "$capture"
printf '%s' '{"packages":[],"variables":[],"connections":[],"certificates":[],"servicesSchedule":[],"alertRules":[],"versionControlAccounts":[]}'
""",
            encoding="utf-8",
        )
        curl.chmod(0o755)
        env = {
            "PATH": f"{mock_bin}:{os.environ['PATH']}",
            "WMIO_CURL_CAPTURE": str(capture),
        }
        result = run(
            [
                "bash", SCRIPTS / "importProjectConfiguration.sh",
                "https://tenant.example", "admin", "SUPER_SECRET", project,
                self.workspace, "NA", trace,
            ],
            env=env,
        )
        return result, capture

    def create_export(self, project="sample"):
        directory = self.workspace / project / "assets/projectConfigs/ProjectConfiguration"
        directory.mkdir(parents=True)
        self.write_json(
            f"{project}/assets/projectConfigs/ProjectConfiguration/ProjectConfiguration_List_Full.json",
            {"metadata": {"source": "dev", "project": "source-id", "generatedOn": 1}},
        )
        values = {
            "configurations_packages.json": [{"packageName": "SupportPkg"}],
            "configurations_variables.json": [],
            "configurations_connections.json": [],
            "configurations_certificates.json": [],
            "configurations_servicesSchedule.json": [],
            "globals_alertRules.json": [],
            "globals_versionControlAccounts.json": [],
        }
        for name, value in values.items():
            self.write_json(f"{project}/assets/projectConfigs/ProjectConfiguration/{name}", value)

    def test_skips_when_no_export_exists(self):
        (self.workspace / "sample").mkdir()
        result, capture = self.invoke()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("No Project configurations to import", result.stdout)
        self.assertFalse(capture.exists())

    def test_builds_expected_payload_and_never_logs_password(self):
        self.create_export()
        result, capture = self.invoke(trace="trace")
        self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        self.assertNotIn("SUPER_SECRET", result.stdout + result.stderr)
        request = json.loads(capture.read_text(encoding="utf-8"))
        self.assertEqual(
            "https://tenant.example/apis/v2/rest/projects/sample/configurations",
            request["url"],
        )
        self.assertEqual("1.0", request["payload"]["apiVersion"])
        self.assertEqual("source-id", request["payload"]["metadata"]["project"])
        self.assertEqual("SupportPkg", request["payload"]["configurations"]["packages"][0]["packageName"])
