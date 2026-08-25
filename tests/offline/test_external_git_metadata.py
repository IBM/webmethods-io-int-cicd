from __future__ import annotations

import shutil

from support import SCRIPTS, WorkspaceTest, git, run


class ExternalGitMetadataTests(WorkspaceTest):
    def setUp(self):
        super().setUp()
        if not shutil.which("yq"):
            self.skipTest("yq is required to exercise saveProjectConfig.sh")

    def repository(self, config):
        remote = self.workspace / "remote.git"
        project = self.workspace / "sample"
        git(self.workspace, "init", "-q", "--bare", remote)
        git(self.workspace, "clone", "-q", remote, project)
        git(project, "config", "user.email", "tests@example.invalid")
        git(project, "config", "user.name", "Offline Tests")
        (project / "project-config.yml").write_text(config, encoding="utf-8")
        git(project, "add", "project-config.yml")
        git(project, "commit", "-q", "-m", "fixture")
        git(project, "branch", "-M", "feature")
        git(project, "push", "-q", "-u", "origin", "feature")
        return project

    def invoke(self):
        return run(
            [
                "bash", SCRIPTS / "github/saveProjectConfig.sh", "sample", "new-id",
                self.workspace, "tester", "feature", "true", "owner/sampleProject",
                "owner/SampleProject", "dev", "user_git", "true", "true", "debug",
            ]
        )

    def test_migrates_legacy_dada_metadata(self):
        project = self.repository(
            "project:\n  project-id: old-id\n  project-name: sample\n  dada:\n    enabled: true\n"
        )
        result = self.invoke()
        self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        content = (project / "project-config.yml").read_text(encoding="utf-8")
        self.assertIn("external-git:", content)
        self.assertIn("enabled: true", content)
        self.assertIn("repository: owner/sampleProject", content)
        self.assertNotIn("dada:", content)

    def test_explicit_false_overrides_stale_legacy_metadata(self):
        project = self.repository(
            "project:\n  project-id: old-id\n  project-name: sample\n  external-git:\n    enabled: false\n  dada:\n    enabled: true\n"
        )
        result = self.invoke()
        self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        content = (project / "project-config.yml").read_text(encoding="utf-8")
        self.assertIn("external-git:\n    enabled: false", content)
        self.assertNotIn("repository:", content)
        self.assertNotIn("dada:", content)

