#!/usr/bin/env python3
"""Capture a bounded POSIX subprocess lifecycle and explicitly selected file witnesses."""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def write_report(destination, report):
    temporary = destination / "report.json.tmp"
    temporary.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temporary.replace(destination / "report.json")


def file_witness(path, content_hash):
    try:
        before = path.lstat()
    except FileNotFoundError:
        return {"exists": False}
    if not stat.S_ISREG(before.st_mode):
        raise ValueError(f"selected path is not a regular file: {path}")
    result = {"exists": True, "size_bytes": before.st_size, "mtime_ns": before.st_mtime_ns}
    if content_hash:
        digest = hashlib.sha256()
        # Refuse a symlink introduced between preflight and opening the witness.
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(descriptor, "rb") as stream:
            opened = os.fstat(stream.fileno())
            if not stat.S_ISREG(opened.st_mode):
                raise ValueError(f"selected path is not a regular file: {path}")
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
            after = os.fstat(stream.fileno())
        identity = lambda value: (value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns,
                                  value.st_ctime_ns)
        if not identity(before) == identity(opened) == identity(after) == identity(path.lstat()):
            raise ValueError(f"selected file changed while hashing: {path}")
        result["sha256"] = digest.hexdigest()
    return result


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description=__doc__,
        epilog="Use -- before COMMAND. Output is a new directory containing report.json and two logs. "
               "The command runs in its original working directory; scripts are not copied. "
               "Only run commands whose execution and recorded argv are authorized.",
    )
    parser.add_argument("--out", type=Path, help="new evidence directory (required)")
    parser.add_argument("--cwd", type=Path, default=Path.cwd(), help="command working directory")
    parser.add_argument("--watch", type=Path, action="append", default=[],
                        help="regular file relative to the invocation directory; may initially be absent")
    parser.add_argument("--hash", action="store_true", help="also hash each selected file's content")
    parser.add_argument("--poll-seconds", type=float, default=0,
                        help="optional progress interval of at least 1 second; 0 disables progress")
    parser.add_argument("--self-test", action="store_true", help="run temporary lifecycle fixtures")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    if args.self_test:
        if argv != ["--self-test"]:
            parser.error("--self-test must be used alone")
        return args
    if args.command[:1] == ["--"]:
        args.command = args.command[1:]
    if args.out is None or not args.command:
        parser.error("--out and COMMAND are required")
    if not math.isfinite(args.poll_seconds) or (args.poll_seconds != 0 and args.poll_seconds < 1):
        parser.error("--poll-seconds must be 0 or a finite interval of at least 1 second")
    if args.hash and not args.watch:
        parser.error("--hash requires at least one --watch file")
    return args


def observe(args):
    if os.name != "posix":
        raise ValueError("POSIX process groups are required (Linux or macOS)")
    cwd = args.cwd.resolve(strict=True)
    if not cwd.is_dir():
        raise ValueError(f"working directory is not a directory: {cwd}")
    # Resolve parents but retain the final component so symlinks cannot hide file type.
    watched = [path.absolute().parent.resolve() / path.name for path in args.watch]
    destination = args.out.absolute().parent.resolve(strict=True) / args.out.name
    if destination.exists() or destination.is_symlink():
        raise ValueError(f"refusing to overwrite existing output: {destination}")
    if len(set(watched)) != len(watched):
        raise ValueError("duplicate selected file path")
    if any(path == destination or destination in path.parents for path in watched):
        raise ValueError("selected files must be outside the evidence directory")
    before = {str(path): file_witness(path, args.hash) for path in watched}
    report = {
        "schema_version": 1, "argv": args.command, "cwd": str(cwd),
        "status": "running", "started_at": utc_now(), "finished_at": None,
        "elapsed_seconds": None, "returncode": None, "signal": None,
        "witness_basis": "metadata-and-sha256" if args.hash else "metadata-only",
        "before": before, "after": {}, "evidence_errors": [],
    }
    destination.mkdir()
    write_report(destination, report)
    started = time.monotonic()
    child = None
    cancelled = None
    cancelled_at = None
    killed = False

    def signal_group(number):
        if child is not None:
            try:
                os.killpg(child.pid, number)
            except ProcessLookupError:
                pass

    def cancel(number, _frame):
        nonlocal cancelled, cancelled_at
        if cancelled is None:
            cancelled, cancelled_at = number, time.monotonic()
        signal_group(number)

    previous = {number: signal.signal(number, cancel) for number in (signal.SIGINT, signal.SIGTERM)}
    try:
        with (destination / "stdout.log").open("xb") as stdout, (destination / "stderr.log").open("xb") as stderr:
            if cancelled is None:
                child = subprocess.Popen(args.command, cwd=cwd, stdout=stdout, stderr=stderr,
                                         start_new_session=True)
                report["pid"] = child.pid
                write_report(destination, report)
                if cancelled is not None:
                    signal_group(cancelled)
                next_progress = started + args.poll_seconds
                while child.poll() is None:
                    now = time.monotonic()
                    if cancelled is not None and now - cancelled_at >= 5 and not killed:
                        signal_group(signal.SIGKILL)
                        killed = True
                    if args.poll_seconds and now >= next_progress:
                        print(f"subprocess-evidence: running for {now - started:.1f}s", file=sys.stderr)
                        next_progress = now + args.poll_seconds
                    time.sleep(0.05)
                report["returncode"] = child.returncode
        report["status"] = "cancelled" if cancelled is not None else (
            "completed" if report["returncode"] == 0 else "failed"
        )
    except OSError as error:
        report["status"] = "observer-failed" if child is not None else "launch-failed"
        report["evidence_errors"].append(str(error))
    finally:
        if cancelled is not None or (child is not None and child.poll() is None):
            signal_group(signal.SIGKILL)
        if child is not None:
            report["returncode"] = child.wait()
        report["signal"] = cancelled
        report["finished_at"] = utc_now()
        report["elapsed_seconds"] = time.monotonic() - started
        for number, handler in previous.items():
            signal.signal(number, handler)
        for path in watched:
            try:
                report["after"][str(path)] = file_witness(path, args.hash)
            except (OSError, ValueError) as error:
                report["evidence_errors"].append(str(error))
        write_report(destination, report)
    print(destination / "report.json")
    if report["evidence_errors"]:
        for error in report["evidence_errors"]:
            print(f"subprocess-evidence: {error}", file=sys.stderr)
        return 1
    if cancelled is not None:
        return 128 + cancelled
    code = report["returncode"]
    return (128 - code if code < 0 else code) if code is not None else 1


def self_test():
    script = str(Path(__file__).resolve())
    with tempfile.TemporaryDirectory(prefix="subprocess-evidence-test.") as temporary:
        root = Path(temporary)
        watched = root / "selected.txt"
        watched.write_text("preserved", encoding="utf-8")

        def run(name, source, *options):
            output = root / name
            result = subprocess.run([sys.executable, script, "--out", str(output), "--cwd", str(root),
                                     *options, "--", sys.executable, "-c", source],
                                    capture_output=True, text=True, timeout=15)
            return result, json.loads((output / "report.json").read_text(encoding="utf-8"))

        result, report = run("success", "import sys; print('ok'); print('diagnostic', file=sys.stderr)",
                             "--watch", str(watched), "--hash")
        assert result.returncode == 0 and not result.stderr
        assert report["before"] == report["after"] and report["returncode"] == 0
        assert (root / "success/stdout.log").read_text().strip() == "ok"
        assert (root / "success/stderr.log").read_text().strip() == "diagnostic"
        result, report = run("failure", "from pathlib import Path; Path('apparent-success').touch(); raise SystemExit(7)")
        assert result.returncode == 7 and report["status"] == "failed" and (root / "apparent-success").exists()
        result, report = run("changed", "from pathlib import Path; Path('selected.txt').write_text('changed')",
                             "--watch", str(watched))
        assert result.returncode == 0 and report["before"] != report["after"]
        result, report = run("silent", "sum(i*i for i in range(1000000))")
        assert result.returncode == 0 and report["elapsed_seconds"] > 0
        result, report = run("waiting", "import time; time.sleep(0.1)")
        assert result.returncode == 0 and report["elapsed_seconds"] >= 0.1
        result, report = run("created", "from pathlib import Path; Path('new-file').write_text('new')",
                             "--watch", str(root / "new-file"), "--hash")
        assert result.returncode == 0
        assert report["before"][str(root / "new-file")] == {"exists": False}
        assert "sha256" in report["after"][str(root / "new-file")]
        launch = subprocess.run([sys.executable, script, "--out", str(root / "launch-failed"), "--",
                                 str(root / "missing-executable")], capture_output=True, timeout=15)
        assert launch.returncode == 1
        assert json.loads((root / "launch-failed/report.json").read_text())["status"] == "launch-failed"
        sentinel = root / "must-not-run"
        result = subprocess.run([sys.executable, script, "--out", str(root / "success"), "--",
                                 sys.executable, "-c", f"open({str(sentinel)!r}, 'w').close()"],
                                capture_output=True, timeout=15)
        assert result.returncode != 0 and not sentinel.exists()
        (root / "selected-link").symlink_to(watched)
        result = subprocess.run([sys.executable, script, "--out", str(root / "bad-watch"),
                                 "--watch", str(root / "selected-link"), "--", "true"],
                                capture_output=True, timeout=15)
        assert result.returncode != 0 and not (root / "bad-watch").exists()

        # The workload writes a readiness marker only after creating a worker that ignores TERM.
        output = root / "cancelled"
        worker = "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); print('ready', flush=True); time.sleep(30)"
        source = ("import subprocess,sys,time; from pathlib import Path; "
                  f"p=subprocess.Popen([sys.executable,'-c',{worker!r}], stdout=subprocess.PIPE); "
                  "p.stdout.readline(); Path('worker.pid').write_text(str(p.pid)); time.sleep(30)")
        with (root / "observer.log").open("w") as log:
            process = subprocess.Popen([sys.executable, script, "--out", str(output), "--cwd", str(root),
                                        "--", sys.executable, "-c", source], stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 10
                while not (root / "worker.pid").exists() and time.monotonic() < deadline:
                    time.sleep(0.05)
                assert (root / "worker.pid").exists()
                process.terminate()
                assert process.wait(timeout=10) == 128 + signal.SIGTERM
                report = json.loads((output / "report.json").read_text())
                assert report["status"] == "cancelled" and report["signal"] == signal.SIGTERM
                worker_pid = int((root / "worker.pid").read_text())
                # An adopted zombie may await the host's reaper, but it cannot continue work.
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    state = subprocess.run(["ps", "-o", "stat=", "-p", str(worker_pid)],
                                           capture_output=True, text=True).stdout.strip()
                    if not state or state.startswith("Z"):
                        break
                    time.sleep(0.05)
                assert not state or state.startswith("Z")
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=10)
    print("Subprocess evidence self-test passed.")


def main(argv):
    args = parse_args(argv)
    if args.self_test:
        self_test()
        return 0
    return observe(args)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except (OSError, ValueError) as error:
        print(f"subprocess-evidence: {error}", file=sys.stderr)
        sys.exit(1)
