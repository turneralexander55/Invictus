#!/usr/bin/env python3
"""Checks for tests/iso/boot-smoke.py without QEMU: a fake root shell on a
Unix socket answers its commands, and each scenario checks the verdict.

    python3 tests/iso/boot-smoke-rules.py     ok/FAIL lines, exit 1 on any failure
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DRIVER = os.path.join(HERE, "boot-smoke.py")
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
from fake_shell import serve  # noqa: E402

HEALTHY = {
    "stty": (0, ""),
    "systemctl is-system-running": (0, "running\n"),
    "pgrep -x calamares": (0, ""),
    "systemctl --failed": (0, ""),
    "systemctl list-jobs": (0, "No jobs running.\n"),
    "journalctl": (0, "[ 1.0] invictus systemd[1]: Started Getty on tty1.\n"
                      "[ 2.0] invictus systemd-timesyncd[5]: Timed out waiting for reply from 1.2.3.4:123.\n"),
    "systemd-analyze": (0, "Startup finished in 1s\n"),
    "systemctl list-sockets": (0, "/run/dbus/system_bus_socket dbus.socket dbus.service\n"),
    "cat /run/user": (0, ""),
}


passed = failed = 0


def check(name, ok):
    global passed, failed
    print(("ok    " if ok else "FAIL  ") + name)
    if ok:
        passed += 1
    else:
        failed += 1


def scenario(name, changes, timeout, want_rc, want_text):
    answers = dict(HEALTHY)
    answers.update(changes)
    with tempfile.TemporaryDirectory() as d:
        srv = serve(os.path.join(d, "shell.sock"), answers)
        p = subprocess.run([sys.executable, DRIVER, d, "--timeout", str(timeout)],
                           capture_output=True, text=True, timeout=timeout + 200)
        srv.close()
        out = p.stdout + p.stderr
        ok = p.returncode == want_rc and all(t in out for t in want_text)
        check(name, ok)
        if not ok:
            print(out)


scenario("a clean boot passes (another program's 'timed out' line is not a boot wait)", {}, 20, 0,
         ["boot finished: running", "live session reached", "boot smoke: passed"])
scenario("a device wait that timed out fails (serial-getty on a missing ttyS0)",
         {"journalctl": (0, "[ 95.0] invictus systemd[1]: dev-ttyS0.device: Job dev-ttyS0.device/start timed out.\n"
                            "[ 95.0] invictus systemd[1]: Timed out waiting for device /dev/ttyS0.\n"
                            "[ 95.0] invictus systemd[1]: Dependency failed for Serial Getty on ttyS0.\n")},
         20, 1, ["FAIL  journal:", "Job dev-ttyS0.device/start timed out", "Dependency failed for Serial Getty"])
scenario("a failed unit fails",
         {"systemctl is-system-running": (1, "degraded\n"),
          "systemctl --failed": (0, "sshd.service loaded failed failed OpenSSH Daemon\n")},
         20, 1, ["FAIL  failed units:", "sshd.service"])
scenario("an sshd socket fails (systemd-ssh-generator's local AF_UNIX socket, design-simple-mode 1.3)",
         {"systemctl list-sockets": (0, "/run/dbus/system_bus_socket dbus.socket dbus.service\n"
                                        "/run/ssh-unix-local/socket sshd-unix-local.socket sshd-unix-local@.service\n")},
         20, 1, ["FAIL  sshd is listening:", "sshd-unix-local.socket"])
scenario("gpg-agent's ssh socket for the pacman keyring is not sshd",
         {"systemctl list-sockets": (0, "/run/dbus/system_bus_socket dbus.socket dbus.service\n"
                                        "/etc/pacman.d/gnupg/S.gpg-agent.ssh gpg-agent-ssh@etc-pacman.d-gnupg.socket gpg-agent@etc-pacman.d-gnupg.service\n")},
         20, 0, ["boot smoke: passed"])
scenario("jobs still queued after boot fail",
         {"systemctl list-jobs": (0, "12 dev-ttyS0.device start running\n")},
         20, 1, ["FAIL  jobs still queued after boot:", "dev-ttyS0.device"])
scenario("no installer by the deadline fails", {"pgrep -x calamares": (1, "")}, 8, 1,
         ["FAIL  live session not reached: no installer within 8 s"])
scenario("a boot that never finishes fails and lists the queued jobs",
         {"systemctl is-system-running": None,
          "systemctl list-jobs": (0, "7 systemd-firstboot.service start running\n")},
         8, 1, ["FAIL  boot not finished within 8 s", "systemd-firstboot.service"])
scenario("no root shell at all fails", {"stty": None, "systemctl": None, "pgrep": None, "journalctl": None},
         6, 1, ["FAIL  no root shell on the second serial port within 6 s"])

print(f"\nboot-smoke rules: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
