"""A fake guest root shell on a Unix socket, for the boot tests' rules
(tests/iso/boot-smoke-rules.py, tests/iso/disk-boot-rules.py). It answers
the commands guest_shell.Shell sends the way a tty does: it echoes the
command line, then the output and the end marker with CRLF line ends.

ANSWERS maps a command prefix to (exit status, output), or to None for a
command that never returns. Give a list of such maps for a guest that
reboots: a command starting with "systemctl reboot" moves to the next map
(the last one stays). The first prefix that matches wins, so put longer
prefixes first. A command no prefix matches gets (0, "").
"""
import re
import socket
import threading

CMD = re.compile(r"echo 'B''([0-9a-f]+)'; (.*); echo 'E''\1' \$\?")


def serve(path, answers, seen=None):
    """Serve ANSWERS on PATH in a thread. SEEN, a list, gets every command run."""
    boots = answers if isinstance(answers, list) else [answers]
    srv = socket.socket(socket.AF_UNIX)
    srv.bind(path)
    srv.listen(1)

    def loop():
        conn, _ = srv.accept()
        boot = 0
        buf = b""
        while True:
            data = conn.recv(4096)
            if not data:
                return
            buf += data
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                text = line.decode()
                if text.startswith("systemctl reboot"):
                    boot = min(boot + 1, len(boots) - 1)
                    continue
                m = CMD.search(text)
                if not m:
                    continue
                tok, cmd = m.group(1), m.group(2)
                if seen is not None:
                    seen.append(cmd)
                ans = next((v for k, v in boots[boot].items() if cmd.startswith(k)), (0, ""))
                if ans is None:  # this command never returns
                    continue
                rc, out = ans
                conn.sendall(line + b"\r\n")
                conn.sendall(f"B{tok}\r\n{out}".replace("\n", "\r\n").replace("\r\r", "\r").encode()
                             + f"E{tok} {rc}\r\n".encode())

    threading.Thread(target=loop, daemon=True).start()
    return srv
