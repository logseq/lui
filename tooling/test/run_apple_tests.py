#!/usr/bin/env python3
"""Require a successful Darwin test helper and a complete Swift Testing run."""

import codecs
import ctypes
from dataclasses import dataclass
import errno
import json
import os
from pathlib import Path
import re
import select
import signal
import subprocess
import sys
import time


# Darwin sys/event.h: include the actual wait status in NOTE_EXIT event data.
NOTE_EXITSTATUS = 0x04000000
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
TERMINAL = re.compile(
    r"(?P<symbol>[✔✘]) Test run with (?P<tests>\d+) tests?(?: in \d+ suites?)? "
    r"(?P<result>passed|failed) after \d+(?:\.\d+)? seconds?"
    r"(?: with \d+ (?:known )?issues?)?\."
)


class Completion:
    def __init__(self):
        self.starts = 0
        self.summaries = []
        self.invalid = False

    def line(self, raw):
        line = ANSI.sub("", raw).strip()
        if line == "◇ Test run started.":
            self.starts += 1
        match = TERMINAL.fullmatch(line)
        if match:
            expected_symbol = "✔" if match["result"] == "passed" else "✘"
            if self.starts != 1 or self.summaries or match["symbol"] != expected_symbol:
                self.invalid = True
            self.summaries.append({
                "tests": int(match["tests"]), "result": match["result"],
                "line": line,
            })
        elif re.match(r"[✔✘] Test run with\b", line):
            self.invalid = True

    def successful(self):
        return (self.starts == 1 and not self.invalid
                and len(self.summaries) == 1
                and self.summaries[0]["tests"] > 0
                and self.summaries[0]["result"] == "passed")


class BSDInfo(ctypes.Structure):
    # Public sys/proc_info.h: PROC_PIDTBSDINFO, including its start-time fields.
    _fields_ = [
        (name, ctypes.c_uint32) for name in (
            "pbi_flags", "pbi_status", "pbi_xstatus", "pbi_pid", "pbi_ppid",
            "pbi_uid", "pbi_gid", "pbi_ruid", "pbi_rgid", "pbi_svuid",
            "pbi_svgid", "rfu_1",
        )
    ] + [("pbi_comm", ctypes.c_char * 16), ("pbi_name", ctypes.c_char * 32)] + [
        (name, ctypes.c_uint32) for name in (
            "pbi_nfiles", "pbi_pgid", "pbi_pjobc", "e_tdev", "e_tpgid",
        )
    ] + [("pbi_nice", ctypes.c_int32), ("pbi_start_tvsec", ctypes.c_uint64),
         ("pbi_start_tvusec", ctypes.c_uint64)]


@dataclass(frozen=True)
class Watch:
    pid: int
    parent: int
    start: tuple
    generation: int
    parent_generation: int


class Processes:
    def __init__(self, root):
        self.libproc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
        self.libproc.proc_listchildpids.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
        self.libproc.proc_listchildpids.restype = ctypes.c_int
        self.libproc.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
        self.libproc.proc_pidpath.restype = ctypes.c_int
        self.libproc.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64,
                                             ctypes.c_void_p, ctypes.c_int]
        self.libproc.proc_pidinfo.restype = ctypes.c_int
        self.queue = select.kqueue()
        self.known = {}
        self.watches = {}
        self.evidence = {}
        try:
            info = self.info(root)
            if info is None or info.pbi_ppid != os.getpid():
                raise ValueError("owned root incarnation was not observed")
            self.watch(info, 0)
        except BaseException:
            self.queue.close()
            raise

    def info(self, pid):
        info = BSDInfo()
        ctypes.set_errno(0)
        size = self.libproc.proc_pidinfo(pid, 3, 0, ctypes.byref(info), ctypes.sizeof(info))
        if size == 0 and ctypes.get_errno() == errno.ESRCH:
            return None
        if size != ctypes.sizeof(info):
            raise OSError("cannot observe process incarnation: " + str(pid))
        if (info.pbi_pid != pid or info.pbi_start_tvsec == 0
                or info.pbi_start_tvusec >= 1000000):
            raise ValueError("invalid process incarnation: " + str(pid))
        return info

    def current(self, record, info=None):
        info = self.info(record.pid) if info is None else info
        if info is not None and (info.pbi_start_tvsec, info.pbi_start_tvusec) != record.start:
            raise ValueError("PID incarnation changed: " + str(record.pid))
        return info

    def watch(self, info, parent_generation):
        if info.pbi_pid in self.known:
            raise ValueError("PID already has an incarnation/watch record")
        record = Watch(info.pbi_pid, info.pbi_ppid,
                       (info.pbi_start_tvsec, info.pbi_start_tvusec),
                       len(self.watches) + 1, parent_generation)
        self.known[record.pid] = record
        self.watches[record.generation] = record
        item = self.evidence[record.generation] = {"status": None}
        if self.current(record) is None:
            item["watch_error"] = "incarnation disappeared before registration"
            return record
        try:
            self.queue.control([select.kevent(
                record.pid, filter=select.KQ_FILTER_PROC, flags=select.KQ_EV_ADD,
                fflags=(select.KQ_NOTE_EXIT | select.KQ_NOTE_FORK
                        | select.KQ_NOTE_EXEC | NOTE_EXITSTATUS),
                udata=record.generation,
            )], 0, 0)
        except OSError as error:
            # Short-lived build children are optional; helper observations are not.
            item["watch_error"] = str(error)
        if self.current(record) is None:
            item["watch_error"] = "incarnation disappeared during registration"
        return record

    def classify(self, record):
        item = self.evidence[record.generation]
        if item.get("watch_error") or self.current(record) is None:
            return
        executable = ctypes.create_string_buffer(4096)
        size = self.libproc.proc_pidpath(record.pid, executable, len(executable))
        # Do not publish a path without the second matching incarnation sample.
        after = self.current(record)
        if (after is None and size > 0
                and (item.get("helper")
                     or Path(os.fsdecode(executable.value)).name == "swiftpm-testing-helper")):
            raise ValueError("helper incarnation lost around path lookup")
        if after is not None and size > 0:
            item["executable"] = os.fsdecode(executable.value)
            if Path(item["executable"]).name == "swiftpm-testing-helper":
                item["helper"] = True

    def discover(self):
        pending = list(self.known.values())
        visited = set()
        while pending:
            parent = pending.pop()
            if (parent.generation in visited
                    or self.evidence[parent.generation]["status"] is not None):
                continue
            visited.add(parent.generation)
            if self.current(parent) is None:
                continue
            count = self.libproc.proc_listchildpids(parent.pid, None, 0)
            if count < 0:
                raise OSError("cannot enumerate owned children")
            children = (ctypes.c_int * (count + 32))()
            count = self.libproc.proc_listchildpids(parent.pid, children, ctypes.sizeof(children))
            if count < 0 or count >= len(children):
                raise OSError("incomplete owned-child observation")
            if self.current(parent) is None:
                continue
            for pid in children[:count]:
                if pid <= 0:
                    continue
                info = self.info(pid)
                if info is None:
                    continue
                new = pid not in self.known
                if pid not in self.known:
                    if info.pbi_ppid != parent.pid:
                        raise ValueError("ambiguous owned-child ancestry: " + str(pid))
                    if self.current(parent) is None:
                        continue
                    self.watch(info, parent.generation)
                record = self.known[pid]
                self.current(record, info)
                self.classify(record)
                if new and self.current(parent) is None:
                    self.evidence[record.generation]["watch_error"] = "parent incarnation lost during admission"
                pending.append(record)

    def observe(self, event):
        record = self.watches.get(event.udata)
        if record is None or record.pid != int(event.ident):
            raise ValueError("uncorrelated process watch event")
        if event.fflags & select.KQ_NOTE_EXIT:
            item = self.evidence[record.generation]
            if item["status"] is not None:
                raise ValueError("duplicate process exit observation")
            raw = int(event.data)
            item["status"] = {
                "watch_generation": record.generation,
                "note_flags": hex(event.fflags),
                "raw_wait_status": raw if event.fflags & NOTE_EXITSTATUS else None,
                "exit_code": (os.waitstatus_to_exitcode(raw & 0xffff)
                              if event.fflags & NOTE_EXITSTATUS else None),
            }

    def collect(self):
        for event in self.queue.control(None, 256, 0.05):
            if event.filter == select.KQ_FILTER_PROC:
                self.observe(event)

    def helpers(self):
        return [dict(self.evidence[record.generation], pid=record.pid,
                     parent=record.parent, incarnation_start=record.start,
                     watch_generation=record.generation,
                     parent_watch_generation=record.parent_generation)
                for record in self.watches.values()
                if "helper" in self.evidence[record.generation]]


def cancel_owned(process, problems):
    if process is None or process.poll() is not None:
        return
    deadline = time.monotonic() + 5
    try:
        # Reserve the last second of the cleanup bound for forced-root reaping.
        process.send_signal(signal.SIGINT)
        try:
            process.wait(timeout=4)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=max(0, deadline - time.monotonic()))
    except (OSError, subprocess.SubprocessError) as error:
        problems.append("owned SwiftPM cleanup failed: " + type(error).__name__)


def run(cancelled):
    command = ["swift", "test", *sys.argv[1:]]
    completion = Completion()
    problems = []
    process = None
    monitor = None
    try:
        if cancelled() is not None:
            raise KeyboardInterrupt
        process = subprocess.Popen(
            command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
        )
        if cancelled() is not None:
            raise KeyboardInterrupt
        monitor = Processes(process.pid)
        decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
        pending = ""
        read_open = True
        monitor.queue.control([select.kevent(
            process.stdout.fileno(), filter=select.KQ_FILTER_READ,
            flags=select.KQ_EV_ADD,
        )], 0, 0)
        next_snapshot = 0
        while read_open or process.poll() is None:
            if cancelled() is not None:
                raise KeyboardInterrupt
            now = time.monotonic()
            if now >= next_snapshot:
                monitor.discover()
                next_snapshot = now + 0.02
            for event in monitor.queue.control(None, 256, 0.02):
                if event.filter == select.KQ_FILTER_PROC:
                    monitor.observe(event)
                    # Darwin does not include the forked child's PID in this
                    # event; discover ancestry immediately, not on a later tick.
                    if event.fflags & (select.KQ_NOTE_FORK | select.KQ_NOTE_EXEC):
                        monitor.discover()
                elif event.filter == select.KQ_FILTER_READ:
                    chunk = os.read(event.ident, 65536)
                    if not chunk:
                        monitor.queue.control([select.kevent(
                            event.ident, filter=select.KQ_FILTER_READ,
                            flags=select.KQ_EV_DELETE,
                        )], 0, 0)
                        read_open = False
                        pending += decoder.decode(b"", final=True)
                        if pending:
                            completion.line(pending)
                        pending = ""
                        continue
                    sys.stdout.buffer.write(chunk)
                    sys.stdout.buffer.flush()
                    pending += decoder.decode(chunk)
                    lines = pending.split("\n")
                    pending = lines.pop()
                    for line in lines:
                        completion.line(line)
        process.wait()
        monitor.collect()
    except (KeyboardInterrupt, OSError, ValueError, subprocess.SubprocessError) as error:
        problems.append("invocation/observation interrupted: " + type(error).__name__ + ": " + str(error))
        cancel_owned(process, problems)
    finally:
        if process is not None and process.stdout is not None:
            process.stdout.close()
        if monitor is not None:
            monitor.queue.close()

    outer_status = process.returncode if process is not None else None
    if cancelled() is not None:
        problems.append("invocation cancelled by " + signal.Signals(cancelled()).name)
    helpers = monitor.helpers() if monitor is not None else []
    if outer_status != 0:
        problems.append("outer swift test did not exit 0")
    if len(helpers) != 1:
        problems.append("expected exactly one observed normal Swift Testing helper")
    elif (helpers[0].get("watch_error") or helpers[0]["status"] is None
          or helpers[0]["status"]["exit_code"] is None):
        problems.append("required helper exit status was not observed")
    elif helpers[0]["status"]["exit_code"] != 0:
        problems.append("Swift Testing helper did not exit 0")
    if not completion.successful():
        problems.append("missing, empty, failed or mismatched terminal Swift Testing run")
    print("apple-test-gate: " + json.dumps({
        "verdict": "FAIL" if problems else "PASS", "command": command,
        "cwd": os.getcwd(), "outer_exit": outer_status, "helpers": helpers,
        "run_starts": completion.starts, "terminal_summaries": completion.summaries,
        "problems": problems,
    }, sort_keys=True), file=sys.stderr, flush=True)
    return 1 if problems else 0


def main():
    if sys.platform != "darwin":
        print("apple-test-gate: Darwin process observation is required", file=sys.stderr)
        return 2
    interrupted = None
    previous = {}

    def interrupt(number, _frame):
        nonlocal interrupted
        # Latch rather than raise across Popen assignment or bounded cleanup.
        if interrupted is None:
            interrupted = number

    try:
        for number in (signal.SIGINT, signal.SIGTERM):
            previous[number] = signal.signal(number, interrupt)
        return run(lambda: interrupted)
    finally:
        for number, handler in previous.items():
            signal.signal(number, handler)


if __name__ == "__main__":
    sys.exit(main())
