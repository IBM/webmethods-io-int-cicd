from __future__ import annotations

from support import REPO_ROOT, WorkspaceTest, run


class StaticValidationTests(WorkspaceTest):
    def test_all_functional_shell_scripts_parse(self):
        failures = []
        scripts = sorted((REPO_ROOT / "pipelines/scripts").rglob("*.sh"))
        self.assertTrue(scripts, "No functional shell scripts were discovered")
        for script in scripts:
            result = run(["bash", "-n", script])
            if result.returncode:
                failures.append(f"{script.relative_to(REPO_ROOT)}: {result.stderr.strip()}")
        self.assertEqual([], failures, "\n".join(failures))

    def test_test_runner_shell_script_parses(self):
        result = run(["bash", "-n", REPO_ROOT / "tests/run.sh"])
        self.assertEqual(0, result.returncode, result.stderr)

    def test_soap_import_accepts_both_success_response_shapes(self):
        expected = ".output.message // .output.status // empty"
        for relative_path in (
            "pipelines/scripts/importAsset.sh",
            "pipelines/scripts/importSoapAPI.sh",
        ):
            with self.subTest(script=relative_path):
                content = (REPO_ROOT / relative_path).read_text(encoding="utf-8")
                self.assertIn(expected, content)
