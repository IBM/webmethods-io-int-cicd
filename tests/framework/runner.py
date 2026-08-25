#!/usr/bin/env python3

"""Discover offline tests and create portable release-validation reports."""

from __future__ import annotations

import contextlib
import html
import io
import json
import os
from pathlib import Path
import sys
import time
import traceback
import unittest
import xml.etree.ElementTree as ET


TESTS_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = TESTS_DIR.parent
OUTPUT_DIR = TESTS_DIR / "output"
LOG_DIR = OUTPUT_DIR / "logs"
REPORT_DIR = OUTPUT_DIR / "reports"
JUNIT_DIR = OUTPUT_DIR / "junit"


class RecordingResult(unittest.TextTestResult):
    """Record timings and captured output while retaining normal CLI output."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.records = []
        self._started = 0.0
        self._stdout = None
        self._stderr = None
        self._stdout_redirect = None
        self._stderr_redirect = None

    def startTest(self, test):  # noqa: N802 - unittest API
        super().startTest(test)
        self._started = time.monotonic()
        self._stdout = io.StringIO()
        self._stderr = io.StringIO()
        self._stdout_redirect = contextlib.redirect_stdout(self._stdout)
        self._stderr_redirect = contextlib.redirect_stderr(self._stderr)
        self._stdout_redirect.__enter__()
        self._stderr_redirect.__enter__()

    def stopTest(self, test):  # noqa: N802 - unittest API
        self._stderr_redirect.__exit__(None, None, None)
        self._stdout_redirect.__exit__(None, None, None)
        duration = time.monotonic() - self._started
        record = getattr(test, "_release_record", None)
        if record is None:
            record = {"status": "passed", "message": ""}
        record.update(
            {
                "id": test.id(),
                "name": str(test),
                "durationSeconds": round(duration, 6),
                "stdout": self._stdout.getvalue(),
                "stderr": self._stderr.getvalue(),
            }
        )
        self.records.append(record)
        super().stopTest(test)

    @staticmethod
    def _failure(test, status, err):
        test._release_record = {
            "status": status,
            "message": "".join(traceback.format_exception(*err)),
        }

    def addFailure(self, test, err):  # noqa: N802 - unittest API
        self._failure(test, "failed", err)
        super().addFailure(test, err)

    def addError(self, test, err):  # noqa: N802 - unittest API
        self._failure(test, "error", err)
        super().addError(test, err)

    def addSkip(self, test, reason):  # noqa: N802 - unittest API
        test._release_record = {"status": "skipped", "message": reason}
        super().addSkip(test, reason)


def write_json(records, elapsed, successful):
    summary = {
        "suite": "offline",
        "successful": successful,
        "durationSeconds": round(elapsed, 6),
        "counts": {
            status: sum(record["status"] == status for record in records)
            for status in ("passed", "failed", "error", "skipped")
        },
        "tests": records,
    }
    path = REPORT_DIR / "offline-summary.json"
    path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


def write_junit(records, elapsed):
    failures = sum(record["status"] in {"failed", "error"} for record in records)
    skipped = sum(record["status"] == "skipped" for record in records)
    suite = ET.Element(
        "testsuite",
        name="offline-release-validation",
        tests=str(len(records)),
        failures=str(failures),
        errors="0",
        skipped=str(skipped),
        time=f"{elapsed:.6f}",
    )
    for record in records:
        case = ET.SubElement(
            suite,
            "testcase",
            name=record["name"],
            classname=record["id"].rsplit(".", 1)[0],
            time=f'{record["durationSeconds"]:.6f}',
        )
        if record["status"] in {"failed", "error"}:
            node = ET.SubElement(case, "failure", message=record["status"])
            node.text = record["message"]
        elif record["status"] == "skipped":
            ET.SubElement(case, "skipped", message=record["message"])
        if record["stdout"]:
            ET.SubElement(case, "system-out").text = record["stdout"]
        if record["stderr"]:
            ET.SubElement(case, "system-err").text = record["stderr"]
    ET.ElementTree(suite).write(
        JUNIT_DIR / "offline.xml", encoding="utf-8", xml_declaration=True
    )


def write_html(summary):
    colors = {"passed": "#16794b", "failed": "#b42318", "error": "#b42318", "skipped": "#946200"}
    rows = []
    for record in summary["tests"]:
        details = "\n".join(
            part for part in (record["message"], record["stdout"], record["stderr"]) if part
        )
        rows.append(
            "<tr>"
            f'<td style="color:{colors[record["status"]]}">{html.escape(record["status"].upper())}</td>'
            f'<td>{html.escape(record["id"])}</td>'
            f'<td>{record["durationSeconds"]:.3f}s</td>'
            f'<td><pre>{html.escape(details)}</pre></td>'
            "</tr>"
        )
    counts = summary["counts"]
    document = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Offline release validation</title>
<style>body{{font-family:system-ui,sans-serif;margin:2rem;color:#172b4d}}table{{border-collapse:collapse;width:100%}}th,td{{border:1px solid #dfe1e6;padding:.6rem;text-align:left;vertical-align:top}}th{{background:#f4f5f7}}pre{{white-space:pre-wrap;max-width:70rem}}.summary{{display:flex;gap:1rem;margin:1rem 0}}.card{{padding:1rem;border:1px solid #dfe1e6;border-radius:.4rem}}</style>
</head><body><h1>Offline release validation</h1>
<div class="summary"><div class="card">Result: <strong>{'PASSED' if summary['successful'] else 'FAILED'}</strong></div>
<div class="card">Passed: {counts['passed']}</div><div class="card">Failed: {counts['failed'] + counts['error']}</div>
<div class="card">Skipped: {counts['skipped']}</div><div class="card">Duration: {summary['durationSeconds']:.3f}s</div></div>
<table><thead><tr><th>Status</th><th>Test</th><th>Duration</th><th>Details</th></tr></thead><tbody>{''.join(rows)}</tbody></table>
</body></html>"""
    (REPORT_DIR / "offline-report.html").write_text(document, encoding="utf-8")


def write_log(records):
    parts = []
    for record in records:
        parts.append(f'[{record["status"].upper()}] {record["id"]} ({record["durationSeconds"]:.3f}s)')
        for label in ("message", "stdout", "stderr"):
            if record[label]:
                parts.append(f"--- {label} ---\n{record[label].rstrip()}")
    (LOG_DIR / "offline.log").write_text("\n".join(parts) + "\n", encoding="utf-8")


def print_summary(summary):
    counts = summary["counts"]
    failed = counts["failed"] + counts["error"]
    result = "PASSED" if summary["successful"] else "FAILED"
    print("\n" + "-" * 72)
    print(" webMethods.io CICD offline release validation")
    print("-" * 72)
    for record in summary["tests"]:
        print(
            f'{record["status"].upper():7} '
            f'{record["durationSeconds"]:7.3f}s  {record["id"]}'
        )
    print("-" * 72)
    print(
        f" Result: {result} | Passed: {counts['passed']} | Failed: {failed} | "
        f"Skipped: {counts['skipped']} | Duration: {summary['durationSeconds']:.3f}s"
    )
    print(" Reports:")
    print(f"   HTML:  {REPORT_DIR / 'offline-report.html'}")
    print(f"   JSON:  {REPORT_DIR / 'offline-summary.json'}")
    print(f"   JUnit: {JUNIT_DIR / 'offline.xml'}")
    print(f"   Log:   {LOG_DIR / 'offline.log'}")
    print("-" * 72)


def main():
    os.chdir(REPO_ROOT)
    for directory in (LOG_DIR, REPORT_DIR, JUNIT_DIR):
        directory.mkdir(parents=True, exist_ok=True)
    suite = unittest.defaultTestLoader.discover(str(TESTS_DIR / "offline"), pattern="test_*.py")
    started = time.monotonic()
    runner = unittest.TextTestRunner(verbosity=2, resultclass=RecordingResult)
    result = runner.run(suite)
    elapsed = time.monotonic() - started
    summary = write_json(result.records, elapsed, result.wasSuccessful())
    write_junit(result.records, elapsed)
    write_html(summary)
    write_log(result.records)
    print_summary(summary)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main())
