from __future__ import annotations

import os

from support import REPO_ROOT, WorkspaceTest, run


CURL_SHIM = REPO_ROOT / "pipelines/scripts/http/curl"
DEV_PIPELINE = REPO_ROOT / "pipelines/synchronizeDEV_pipeline.yml"
DEV_CONFIG = REPO_ROOT / "configs/env/dev.yml"


class TenantAuthenticationTests(WorkspaceTest):
    def setUp(self):
        super().setUp()
        self.capture = self.workspace / "curl-arguments.txt"
        self.fake_curl = self.write(
            "fake-curl",
            """#!/bin/bash
printf '%s\\n' "$@" > "$CURL_ARGUMENT_CAPTURE"
printf 'ok'
""",
            executable=True,
        )

    def invoke(self, generation: str | None, api_key: str | None, url: str):
        env = {
            "IWHI_CURL_BIN": str(self.fake_curl),
            "IWHI_BASE_URL": "https://tenant.example",
            "CURL_ARGUMENT_CAPTURE": str(self.capture),
        }
        if generation is not None:
            env["TENANT_GENERATION"] = generation
        if api_key is not None:
            env["INSTANCE_API_KEY"] = api_key
        result = run(
            [
                CURL_SHIM,
                "--silent",
                "--user",
                "admin:SECRET_PASSWORD",
                url,
            ],
            env=env,
        )
        arguments = self.capture.read_text(encoding="utf-8") if self.capture.exists() else ""
        return result, arguments

    def test_missing_generation_defaults_to_gen1_basic_auth(self):
        result, arguments = self.invoke(None, None, "https://tenant.example/apis/v1/rest/projects")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("--user\nadmin:SECRET_PASSWORD\n", arguments)
        self.assertNotIn("x-instance-api-key", arguments)

    def test_gen2_replaces_basic_auth_with_instance_api_key(self):
        result, arguments = self.invoke("gen2", "SECRET_API_KEY", "https://tenant.example/apis/v1/rest/projects")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertNotIn("--user", arguments)
        self.assertNotIn("SECRET_PASSWORD", arguments)
        self.assertIn("x-instance-api-key: SECRET_API_KEY", arguments)

    def test_gen2_fails_before_request_when_key_is_missing(self):
        result, arguments = self.invoke("gen2", None, "https://tenant.example/apis/v1/rest/projects")
        self.assertEqual(2, result.returncode)
        self.assertIn("requires the secret INSTANCE_API_KEY", result.stderr)
        self.assertEqual("", arguments)

    def test_non_tenant_request_is_not_modified(self):
        result, arguments = self.invoke("gen2", "SECRET_API_KEY", "https://api.github.com/repos/example/repo")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("--user\nadmin:SECRET_PASSWORD\n", arguments)
        self.assertNotIn("x-instance-api-key", arguments)

    def test_invalid_generation_fails_before_request(self):
        result, arguments = self.invoke("future", "SECRET_API_KEY", "https://tenant.example/apis/v1/rest/projects")
        self.assertEqual(2, result.returncode)
        self.assertIn("Unsupported tenant generation", result.stderr)
        self.assertEqual("", arguments)

    def test_dev_config_and_pipeline_enable_gen2_without_embedding_key(self):
        config = DEV_CONFIG.read_text(encoding="utf-8")
        pipeline = DEV_PIPELINE.read_text(encoding="utf-8")
        self.assertIn('generation: "gen2"', config)
        self.assertIn('.tenant.generation // "gen1"', pipeline)
        self.assertIn('export TENANT_GENERATION="$(tenant_generation)"', pipeline)
        self.assertIn('INSTANCE_API_KEY: $(dev_instance_api_key)', pipeline)
        self.assertNotIn("x-instance-api-key:", pipeline)

    def test_play_config_exercises_gen1_default(self):
        play_config = (REPO_ROOT / "configs/env/play.yml").read_text(encoding="utf-8")
        self.assertNotIn("generation:", play_config)

    def test_environment_pipelines_load_generation_with_gen1_default(self):
        expectations = {
            "initialize_pipeline.yml": "play",
            "initialize_runtime.yml": "play",
            "sychronizeFeatureBranch_pipeline.yml": "play",
            "synchronizeDEV_pipeline.yml": "dev",
            "sychronizeToQA_pipeline.yml": "qa",
        }
        for filename, environment in expectations.items():
            with self.subTest(filename=filename):
                content = (REPO_ROOT / "pipelines" / filename).read_text(encoding="utf-8")
                self.assertIn('.tenant.generation // "gen1"', content)
                self.assertIn('export TENANT_GENERATION="$(tenant_generation)"', content)
                self.assertIn(f"INSTANCE_API_KEY: $({environment}_instance_api_key)", content)
                self.assertIn("pipelines/scripts/http:${PATH}", content)

    def test_api_import_accepts_gen1_and_gen2_success_responses(self):
        for filename in ("importAsset.sh", "importSoapAPI.sh"):
            with self.subTest(filename=filename):
                content = (REPO_ROOT / "pipelines/scripts" / filename).read_text(encoding="utf-8")
                self.assertIn(".output.message // .output.status // empty", content)


if __name__ == "__main__":
    import unittest

    unittest.main()
