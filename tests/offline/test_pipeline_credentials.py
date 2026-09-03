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
