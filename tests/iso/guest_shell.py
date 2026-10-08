"""The root shell on a QEMU guest's second serial port, shared by
tests/iso/boot-smoke.py (the live ISO) and tests/iso/disk-boot.py (the
installed disk). QEMU serves the port as a Unix socket (RUNDIR/shell.sock);
the guest runs a root shell on /dev/ttyS1 (systemd.debug_shell=/dev/ttyS1
on the live ISO, debug-shell.service with TTYPath=/dev/ttyS1 on the test
disk image).
"""
import re
import secrets
import socket
import time

# systemd's own journal lines (PID 1) that mean a job waited until its
# timeout, or a unit failed. Other programs' "timed out" lines (an NTP
# server that does not answer, say) are not boot waits.
BAD_JOURNAL = re.compile(
    r" systemd\[1\]: .*(Timed out waiting for|[Jj]ob .* timed out|timed out\.|"
    r"Dependency failed for|Failed to start |Failed with result)")

# sshd's own units (sshd*.socket, sshd-unix-local@.service, ssh-access.socket),
# not any line containing "ssh": gpg-agent's gpg-agent-ssh@ socket for the
# pacman keyring is not a server.
SSHD_UNIT = re.compile(r"^(sshd[\w@.-]*|ssh-[\w@.-]*)\.(socket|service)$")


def sshd_socket_lines(listing):
    """The lines of `systemctl list-sockets` output that name an sshd unit."""
    return [ln for ln in listing.splitlines() if any(SSHD_UNIT.match(t) for t in ln.split())]


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

    def send(self, cmd):
        """Send CMD and do not wait for it (a reboot never answers)."""
        self.s.sendall((cmd + "\n").encode())

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


def wait_root_shell(sh, deadline):
    """Retry until the guest's shell answers; True when it does, False at the deadline."""
    while True:
        r = sh.run("stty -echo cols 250 2>/dev/null; export SYSTEMD_COLORS=0 SYSTEMD_PAGER= SYSTEMD_URLIFY=0", 5)
        if r is not None:
            return True
        if time.monotonic() > deadline:
            return False
