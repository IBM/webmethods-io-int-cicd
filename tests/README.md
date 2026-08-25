# Offline release validation

This directory contains the Master-repository test framework. It invokes the
existing functional scripts as external programs and does not modify their
runtime behaviour.

Run the complete offline suite from the repository root:

```bash
./tests/run.sh offline
```

Generated evidence is written below `tests/output/`:

- `logs/offline.log`
- `reports/offline-summary.json`
- `reports/offline-report.html`
- `junit/offline.xml`

The command exits non-zero when any test fails. No tenant, GitHub account,
remote repository, or customer environment is required.

## GitHub release validation

`.github/workflows/release-validation.yml` executes the same offline suite for:

- pull requests targeting `main`;
- pushes to `main`;
- tags beginning with `v` or `test`;
- manual workflow runs.

The job displays the shell report during execution, writes a compact result to
the GitHub job summary, and uploads the HTML, JSON, JUnit, and raw log evidence
for 30 days. Evidence is published even when validation fails; the final gate
then fails the job and prevents release promotion.

A tag-triggered workflow validates a tag after it has been pushed. For a formal
release, first validate the candidate commit through a pull request or manual
run, then create the tag and require its validation run to pass before creating
the GitHub release.
