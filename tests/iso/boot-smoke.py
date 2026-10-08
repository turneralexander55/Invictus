#!/usr/bin/env python3
"""Boot smoke test driver (tests/iso/boot-smoke.sh starts QEMU).

    boot-smoke.py RUNDIR [--timeout SECONDS]

Talks to the root debug shell that systemd.debug_shell=/dev/ttyS1 starts on
the guest's second serial port (RUNDIR/shell.sock) and fails when:
  - the shell, the end of boot or the live session's installer is not there
    before the deadline (default 600 s from the start of this script);
  - any unit failed, any job timed out or a dependency failed;
  - jobs are still queued once boot is done (something is waiting).
It writes RUNDIR/journal.txt, RUNDIR/report.txt and RUNDIR/screen.png.
"""
import argparse
import os
import re
import secrets
import socket
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))

# systemd's own journal lines (PID 1) that mean a job waited until its
# timeout, or a unit failed. Other programs' "timed out" lines (an NTP
# server that does not answer, say) are not boot waits.
BAD_JOURNAL = re.compile(
    r" systemd\[1\]: .*(Timed out waiting for|[Jj]ob .* timed out|timed out\.|"
    r"Dependency failed for|Failed to start |Failed with result)")


class Shell:
    def __init__(self, path, deadline):
        self.deadline = deadline
        while True:
            try:
                self.s = socket.socket(socket.AF_UNIX)
                self.s.connect(path)
                break
            except OSError:
                self.s.close()
                if time.monotonic() > deadline:
                    raise TimeoutError(f"no serial socket at {path}")
                time.sleep(1)
        self.buf = b""

    def run(self, cmd, timeout):
        """Run CMD in the guest shell; (exit status, output) or None on timeout."""
        tok = secrets.token_hex(4)
        # The markers are split in the command so the tty's echo of the
        # command line never matches them.
        line = f"echo 'B''{tok}'; {cmd}; echo 'E''{tok}' $?\n"
        self.s.sendall(line.encode())
        end = min(time.monotonic() + timeout, self.deadline)
        pat = re.compile(rb"B" + tok.encode() + rb"\r?\n(.*?)E" + tok.encode() + rb" (\d+)", re.S)
        while time.monotonic() < end:
            m = pat.search(self.buf)
            if m:
                self.buf = self.buf[m.end():]
                return int(m.group(2)), m.group(1).decode("utf-8", "replace").replace("\r", "")
            self.s.settimeout(max(0.1, end - time.monotonic()))
            try:
                data = self.s.recv(65536)
            except socket.timeout:
                continue
            if not data:
                raise ConnectionError("serial socket closed (QEMU stopped?)")
            self.buf += data
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--timeout", type=int, default=600)
    a = ap.parse_args()
    t0 = time.monotonic()
    deadline = t0 + a.timeout
    run = a.rundir
    problems, report = [], []

    def say(msg):
        msg = f"[{time.monotonic() - t0:6.0f}s] {msg}"
        print(msg, flush=True)
        report.append(msg)

    def finish():
        try:
            subprocess.run([sys.executable, os.path.join(HERE, "qmp.py"), os.path.join(run, "qmp.sock"),
                            "shot", os.path.join(run, "screen.png")], timeout=30, check=False)
        except Exception:  # a screenshot is a nice-to-have
            pass
        for p in problems:
            say(f"FAIL  {p}")
        say("boot smoke: " + ("FAILED" if problems else "passed"))
        with open(os.path.join(run, "report.txt"), "w") as f:
            f.write("\n".join(report) + "\n")
        sys.exit(1 if problems else 0)

    try:
        sh = Shell(os.path.join(run, "shell.sock"), deadline)
    except TimeoutError as e:
        problems.append(str(e))
        finish()
    # 1. The debug shell comes up early in boot; retry until it answers.
    while True:
        r = sh.run("stty -echo cols 250 2>/dev/null; export SYSTEMD_COLORS=0 SYSTEMD_PAGER= SYSTEMD_URLIFY=0", 5)
        if r is not None:
            break
        if time.monotonic() > deadline:
            problems.append(f"no root shell on the second serial port within {a.timeout} s "
                            "(the kernel or the initramfs did not get to systemd; see screen.png)")
            finish()
    say("root shell up")

    # 2. The end of boot: every job done (running or degraded).
    r = sh.run("systemctl is-system-running --wait", deadline - time.monotonic())
    if r is None:
        _, jobs = sh.run("systemctl list-jobs --no-legend --full", 30) or (0, "?")
        problems.append(f"boot not finished within {a.timeout} s; jobs still queued:\n{jobs}")
    else:
        say(f"boot finished: {r[1].strip()}")

    # 3. The live session: the installer is running (Hyprland or cage).
    while time.monotonic() < deadline:
        r = sh.run("pgrep -x calamares >/dev/null", 15)
        if r is not None and r[0] == 0:
            say("live session reached: the installer is running")
            break
        time.sleep(5)
    else:
        problems.append(f"live session not reached: no installer within {a.timeout} s")

    # 4. What went wrong on the way, if anything.
    grace = time.monotonic() + 120
    sh.deadline = max(sh.deadline, grace)
    r = sh.run("systemctl --failed --plain --no-legend --full", 30)
    if r and r[1].strip():
        problems.append("failed units:\n" + r[1].rstrip())
    r = sh.run("systemctl list-jobs --no-legend --full", 30)
    if r and r[1].strip() and "No jobs" not in r[1]:
        problems.append("jobs still queued after boot:\n" + r[1].rstrip())
    # sshd is off on the live image too (design-simple-mode 1.3): no system
    # socket for it, including systemd-ssh-generator's AF_UNIX and AF_VSOCK ones.
    r = sh.run("systemctl list-sockets --all --no-legend --full", 30)
    if r is None:
        problems.append("could not list the system's sockets")
    else:
        # Match sshd's own units (sshd*.socket, sshd-unix-local@.service,
        # ssh-access.socket), not any line containing "ssh": gpg-agent's
        # gpg-agent-ssh@ socket for the pacman keyring is not a server.
        ssh_unit = re.compile(r"^(sshd[\w@.-]*|ssh-[\w@.-]*)\.(socket|service)$")
        hits = [ln for ln in r[1].splitlines() if any(ssh_unit.match(t) for t in ln.split())]
        if hits:
            problems.append("sshd is listening:\n" + "\n".join(hits))
    r = sh.run("journalctl -b --no-pager -o short-monotonic", 90)
    if r:
        with open(os.path.join(run, "journal.txt"), "w") as f:
            f.write(r[1])
        bad = [ln for ln in r[1].splitlines() if BAD_JOURNAL.search(ln)]
        if bad:
            problems.append("journal:\n" + "\n".join(bad[:40]))
    for cmd in ("systemd-analyze time", "systemd-analyze blame --no-pager | head -n 15",
                "cat /run/user/1000/invictus-live-session.log 2>/dev/null | tail -n 20"):
        r = sh.run(cmd, 30)
        if r:
            say(f"$ {cmd}\n{r[1].rstrip()}")
    finish()


if __name__ == "__main__":
    main()
