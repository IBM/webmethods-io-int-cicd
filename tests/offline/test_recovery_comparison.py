from __future__ import annotations

import json
import zipfile

from support import SCRIPTS, WorkspaceTest, git, run


class RecoveryComparisonTests(WorkspaceTest):
    def setUp(self):
        super().setUp()
        self.repo = self.workspace / "repo"
        self.repo.mkdir()
        git(self.repo, "init", "-q")
        git(self.repo, "config", "user.email", "tests@example.invalid")
        git(self.repo, "config", "user.name", "Offline Tests")

    def commit(self, branch, generated_on, description="unchanged", archive_time=(2026, 1, 1, 0, 0, 0)):
        git(self.repo, "checkout", "-q", "-B", branch)
        config = self.repo / "assets/projectConfigs/ProjectConfiguration/ProjectConfiguration_List_Full.json"
        config.parent.mkdir(parents=True, exist_ok=True)
        config.write_text(
            json.dumps({"metadata": {"generatedOn": generated_on}, "configurations": {"variables": []}}),
            encoding="utf-8",
        )
        archive = self.repo / "assets/flowservices/Sample.zip"
        archive.parent.mkdir(parents=True, exist_ok=True)
        node = (
            '<record><value name="description">%s</value>'
            '<number name="createdDate">%s</number>'
            '<value name="lastModifiedDate">%s</value></record>'
            % (description, generated_on, generated_on)
        )
        with zipfile.ZipFile(archive, "w") as bundle:
            info = zipfile.ZipInfo("pkg_0123456789abcdef0123456789abcdef_exported/ns/node.ndf", archive_time)
            bundle.writestr(info, node)
            bundle.writestr("pkg_0123456789abcdef0123456789abcdef_exported/sig.txt", str(generated_on))
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", branch)

    def compare(self, expected, actual):
        return run(
            ["python3", SCRIPTS / "compareRecoverySnapshot.py", expected, actual],
            cwd=self.repo,
        )

    def test_ignores_generated_json_and_zip_audit_metadata(self):
        self.commit("expected", 1000, archive_time=(2026, 1, 1, 0, 0, 0))
        self.commit("actual", 2000, archive_time=(2026, 8, 25, 12, 30, 0))
        result = self.compare("expected", "actual")
        self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        self.assertEqual("", result.stdout)

    def test_detects_meaningful_flowservice_change(self):
        self.commit("expected", 1000, description="original")
        self.commit("actual", 2000, description="changed")
        result = self.compare("expected", "actual")
        self.assertEqual(1, result.returncode)
        self.assertIn("M\tassets/flowservices/Sample.zip", result.stdout)

    def test_detects_added_asset(self):
        self.commit("expected", 1000)
        self.commit("actual", 2000)
        added = self.repo / "assets/extra.json"
        added.write_text('{"value": true}\n', encoding="utf-8")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "added asset")
        result = self.compare("expected", "actual")
        self.assertEqual(1, result.returncode)
        self.assertIn("A\tassets/extra.json", result.stdout)
