"""Run with python3 -m unittest discover -s tests (requires PyYAML, bash, git and curl)."""
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/run-command.yml"
CONFIG = yaml.safe_load(WORKFLOW.read_text())
JOBS = CONFIG["jobs"]


def step(job, step_id):
    return next(s for s in JOBS[job]["steps"] if s.get("id") == step_id)


def run_step(source, directory, **env):
    return subprocess.run(["bash", "-e", "-c", source], cwd=directory,
                          env={**os.environ, **env}, capture_output=True, text=True)


class WorkflowTests(unittest.TestCase):
    def test_output_publication_is_opt_in(self):
        inputs = CONFIG["on"]["workflow_dispatch"]["inputs"]
        for name in ("publish_output", "preview_output"):
            with self.subTest(name=name):
                self.assertEqual(inputs[name]["type"], "boolean")
                self.assertIs(inputs[name]["default"], False)
        preview = step("run", "preview")
        self.assertEqual(preview["if"], "${{ !cancelled() && inputs.preview_output && "
                         "(steps.command.outcome == 'success' || steps.command.outcome == 'failure') }}")

    def test_public_preview(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, "result.txt")
            for length in (0, 8192, 8193):
                with self.subTest(length=length):
                    content = ("::warning::example\n" + "x" * length)[:length]
                    path.write_text(content)
                    preview = run_step(step("run", "preview")["run"], directory)
                    self.assertEqual(preview.returncode, 0, preview.stderr)
                    header, body = preview.stdout.split("\n", 1)
                    self.assertRegex(header, r"^::stop-commands::[0-9a-f]{32}$")
                    marker = header.split("::")[-1]
                    note = "（仅显示前 8 KiB）\n" if length > 8192 else ""
                    self.assertEqual(body, f"{content[:8192]}\n{note}::{marker}::\n")

    def test_timeout(self):
        check = step("validate", "timeout")["run"]
        self.assertEqual(JOBS["run"]["needs"], "validate")
        self.assertEqual(JOBS["run"]["timeout-minutes"],
                         "${{ fromJSON(needs.validate.outputs.minutes) }}")
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory, "output")
            for value in ("1", "20", "350", "351", "0", "-1", "02", "1.5", "no", "1+1"):
                with self.subTest(value=value):
                    output.write_text("")
                    result = run_step(check, directory, MINUTES=value, GITHUB_OUTPUT=str(output))
                    valid = value in ("1", "20", "350")
                    self.assertEqual(result.returncode == 0, valid)
                    self.assertEqual(output.read_text(), f"minutes={value}\n" if valid else "")

    def test_result_conditions(self):
        save = step("run", "save-result")["if"]
        write = JOBS["write-result"]["if"]
        self.assertIn("steps.command.outcome == 'failure'", save)
        self.assertIn("always() && !cancelled()", write)
        self.assertIn("needs.run.result == 'failure'", write)
        self.assertIn("needs.run.outputs.result-artifact != ''", write)
        for action in JOBS["run"]["steps"]:
            if action.get("uses", "").startswith("actions/upload-artifact@"):
                self.assertIn("inputs.publish_output", action["if"])

    def test_command_and_writeback(self):
        for status in (0, 23):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                tmp = Path(directory)
                artifact = tmp / "command-result"
                artifact.mkdir()
                command = f"echo stdout; echo stderr >&2; exit {status}"
                event = tmp / "event.json"
                event.write_text(json.dumps({"inputs": {"command": command}}))
                summary = tmp / "summary"
                result = run_step(step("run", "command")["run"], artifact,
                                  GITHUB_EVENT_PATH=str(event), GITHUB_STEP_SUMMARY=str(summary))
                self.assertEqual(result.stdout + result.stderr, "")
                self.assertEqual(summary.read_text(), f"命令退出码：{status}\n")
                self.assertEqual(result.returncode, status)
                # Use only a temporary local repository as the push destination.
                remote = tmp / "remote.git"
                checkout = tmp / "checkout"
                subprocess.run(["git", "init", "--bare", "-q", remote], check=True)
                subprocess.run(["git", "init", "-q", "-b", "test", checkout], check=True)
                subprocess.run(["git", "-C", checkout, "remote", "add", "origin", remote], check=True)
                write = JOBS["write-result"]["steps"][-1]["run"]
                result = run_step(write, checkout, RUNNER_TEMP=directory, GITHUB_REF="refs/heads/test")
                self.assertEqual(result.returncode, 0, result.stderr)
                saved = subprocess.check_output(["git", "-C", remote, "show", "test:result.txt"])
                self.assertEqual(saved, b"stdout\nstderr\n")


class UploadTests(unittest.TestCase):
    def test_multipart_and_error_responses(self):
        filename = "sample file, part; 1.apk"
        with tempfile.TemporaryDirectory() as directory:
            tmp = Path(directory)
            fixture = tmp / "fixture.zip"
            with zipfile.ZipFile(fixture, "w") as archive:
                archive.writestr(filename, b"plain text fixture")
            # Pass production form arguments to curl. Its generated libcurl
            # calls expose the parsed fields without opening an HTTP connection.
            wrapper = tmp / "curl"
            wrapper.write_text("""#!/bin/bash
set -eu
url=${!#}
case "$url" in
  https://archive.org/download/*) cp "$FIXTURE" z.zip; exit 0 ;;
  https://temp.sh/upload) service=first ;;
  https://litterbox.catbox.moe/resources/internals/api.php) service=second ;;
  *) echo 'unexpected destination' >&2; exit 97 ;;
esac
"$REAL_CURL" -q --proto '=file' --libcurl "$CAPTURE/$service.c" "${@:1:$#-1}" file:///dev/null
case "$service:$SCENARIO" in
  second:http-error) exit 22 ;;
  second:error-body) echo rejected-body-must-stay-private ;;
  *) echo https://example.invalid/file ;;
esac
""")
            wrapper.chmod(0o700)
            for scenario in ("http-error", "error-body"):
                with self.subTest(scenario=scenario):
                    capture = tmp / scenario
                    capture.mkdir()
                    result = subprocess.run(
                        ["bash", ROOT / "fetch_mc.sh"], cwd=tmp,
                        env={"PATH": f"{tmp}:{os.defpath}", "GITHUB_TOKEN": "fixture",
                             "FIXTURE": str(fixture), "CAPTURE": str(capture),
                             "REAL_CURL": shutil.which("curl"), "SCENARIO": scenario},
                        capture_output=True, text=True, timeout=10)
                    for service, field in (("first", "file"), ("second", "fileToUpload")):
                        parsed = (capture / f"{service}.c").read_text()
                        self.assertEqual(parsed.count("curl_mime_filedata("), 1)
                        self.assertRegex(parsed, rf'curl_mime_filedata\(\w+, "\./{re.escape(filename)}"\)')
                        self.assertRegex(parsed, rf'curl_mime_name\(\w+, "{field}"\)')
                        self.assertIn("CURLOPT_FAILONERROR", parsed)
                    self.assertNotEqual(result.returncode, 0)
                    if scenario == "error-body":
                        self.assertIn("没有返回下载链接", result.stderr)
                    self.assertNotIn("rejected-body", result.stdout + result.stderr)
                    self.assertNotIn("=== upload github release", result.stdout)
