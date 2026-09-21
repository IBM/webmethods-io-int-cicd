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
if [[ "$url" == *'/configurations/packages' ]]; then
  cp "$WMIO_PACKAGES_RESPONSE" "$output"
  printf '200'
elif [[ "$url" == *'/configurations' ]]; then
  cp "$WMIO_CONFIG_RESPONSE" "$output"
  printf '%s' "${WMIO_CONFIG_STATUS:-200}"
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
                "WMIO_PACKAGES_RESPONSE": str(response),
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

    def test_export_reuses_previously_downloaded_project_configuration(self):
        (self.project / "project-config.yml").write_text(
            "project:\n"
            "  project-id: legacy-id\n"
            "  project-name: sample\n"
            "  external-git:\n"
            "    enabled: false\n",
            encoding="utf-8",
        )
        cached_config = self.project / "assets/projectConfigs/ProjectConfiguration/ProjectConfiguration_List_Full.json"
        cached_config.parent.mkdir(parents=True)
        cached_config.write_text(
            json.dumps({
                "metadata": {"project": "cached-api-id"},
                "configurations": {"packages": None},
            }),
            encoding="utf-8",
        )
        self.write(
            "mock-bin/curl",
            "#!/bin/bash\necho 'curl must not be called when cached configuration is valid' >&2\nexit 99\n",
            executable=True,
        )

        result = run(
            [
                "bash", SCRIPTS / "exportDadaMetadata.sh",
                "https://tenant.example", "admin", "SECRET", "sample",
                self.project, "owner", "PAT", self.configs, "debug",
            ],
            env={"PATH": f"{self.mock_bin}:{os.environ['PATH']}"},
        )

        self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        self.assertIn("Reusing exported project configuration", result.stderr)
        project_config = (self.project / "project-config.yml").read_text(encoding="utf-8")
        self.assertIn("project-id: cached-api-id", project_config)

    def test_export_falls_back_to_package_endpoint_when_full_configuration_fails(self):
        error_response = self.write_json(
            "configuration-error.json", {"code": 502, "message": "Bad Gateway"}
        )
        packages_response = self.write_json("packages-response.json", {"output": None})

        result = run(
            [
                "bash", SCRIPTS / "exportDadaMetadata.sh",
                "https://tenant.example", "admin", "SECRET", "sample",
                self.project, "owner", "PAT", self.configs, "debug",
            ],
            env={
                "PATH": f"{self.mock_bin}:{os.environ['PATH']}",
                "WMIO_CONFIG_RESPONSE": str(error_response),
                "WMIO_CONFIG_STATUS": "502",
                "WMIO_PACKAGES_RESPONSE": str(packages_response),
            },
        )

        self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        self.assertIn("querying imported packages directly", result.stderr)
        self.assertFalse(
            (self.project / "assets/dada/config/imported-package-metadata.yml").exists()
        )
