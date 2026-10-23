from __future__ import annotations

from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
PIPELINES = REPO_ROOT / "pipelines"


def pipeline(name: str) -> str:
    return (PIPELINES / name).read_text(encoding="utf-8")


class PipelineCredentialRoutingTests(unittest.TestCase):
    def assert_uses_only(self, filename: str, expected: str) -> None:
        content = pipeline(filename)
        self.assertIn(f"$({expected}_admin_password)", content)
        self.assertNotIn("$(admin_password)", content)
        for environment in {"play", "dev", "qa", "prod"} - {expected}:
            self.assertNotIn(f"$({environment}_admin_password)", content)

        secret_lines = [
            line.strip()
            for line in content.splitlines()
            if f"$({expected}_admin_password)" in line
        ]
        self.assertTrue(secret_lines)
        self.assertTrue(
            all(line.startswith("TENANT_ADMIN_PASSWORD:") for line in secret_lines),
            f"{filename} embeds a tenant secret directly in a generated shell script",
        )
        self.assertIn('$TENANT_ADMIN_PASSWORD', content)

    def test_play_pipelines_use_play_tenant_secret(self):
        for filename in (
            "initialize_pipeline.yml",
            "initialize_runtime.yml",
            "sychronizeFeatureBranch_pipeline.yml",
        ):
            with self.subTest(filename=filename):
                self.assert_uses_only(filename, "play")

    def test_dev_import_uses_dev_tenant_secret(self):
        self.assert_uses_only("synchronizeDEV_pipeline.yml", "dev")

    def test_qa_import_uses_qa_tenant_secret(self):
        self.assert_uses_only("sychronizeToQA_pipeline.yml", "qa")

    def test_import_pipelines_delegate_project_preparation_and_fail_fast(self):
        for filename in ("synchronizeDEV_pipeline.yml", "sychronizeToQA_pipeline.yml"):
            with self.subTest(filename=filename):
                content = pipeline(filename)
                self.assertNotIn("projectHasAPIs", content)
                self.assertNotIn("assetsDeclareApis", content)
                self.assertNotIn("repositoryContainsApis", content)
                self.assertIn("prepareImportProject.sh", content)
                self.assertIn("Project preparation failed.", content)

    def test_project_preparation_owns_rest_and_soap_detection(self):
        preparation = (PIPELINES / "scripts" / "prepareImportProject.sh").read_text(
            encoding="utf-8"
        )
        creation = (PIPELINES / "scripts" / "createProject.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn('assets/rest_api/*.zip', preparation)
        self.assertIn('assets/soap_api/*.zip', preparation)
        self.assertIn("synchProject", preparation)
        self.assertIn("assetTypeList", preparation)
        self.assertIn("REST API exports detected", creation)

    def test_dynamic_testing_selects_password_without_logging_it(self):
        content = pipeline("InitiateTesting.yml")
        for environment in ("play", "dev", "qa", "prod"):
            self.assertIn(
                f"{environment.upper()}_ADMIN_PASSWORD: $({environment}_admin_password)",
                content,
            )
        self.assertIn("variable=tenant_admin_password;issecret=true", content)
        self.assertIn('password=$(tenant_admin_password)', content)
        self.assertNotIn('password=$(admin_password)', content)
        self.assertNotIn('echo "newman run', content)


if __name__ == "__main__":
    unittest.main()
