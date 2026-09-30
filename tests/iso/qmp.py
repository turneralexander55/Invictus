#!/usr/bin/env python3
"""Tiny QMP client for tests/iso/boot-qemu.sh: screenshots and key presses.

    qmp.py SOCKET shot FILE.png        screendump as PNG (FILE next to the socket)
    qmp.py SOCKET keys KEY [KEY...]    press keys one after another
                                       (QEMU qcode names: ret, tab, spc, e,
                                       end, esc, down; a combo is joined
                                       with +, e.g. shift+tab, ctrl+alt+f2)
    qmp.py SOCKET type TEXT            type plain ASCII text
    qmp.py SOCKET quit                 stop QEMU
"""
import json
import socket
import sys
import time

SHIFTED = {"_": "minus", "+": "equal", ":": "semicolon", '"': "apostrophe", "?": "slash",
           "<": "comma", ">": "dot", "!": "1", "@": "2", "#": "3", "$": "4", "%": "5",
           "^": "6", "&": "7", "*": "8", "(": "9", ")": "0", "{": "bracket_left",
           "}": "bracket_right", "|": "backslash", "~": "grave_accent"}
PLAIN = {" ": "spc", "-": "minus", "=": "equal", ";": "semicolon", "'": "apostrophe",
         "/": "slash", ",": "comma", ".": "dot", "[": "bracket_left", "]": "bracket_right",
         "\\": "backslash", "`": "grave_accent", "\n": "ret"}


class QMP:
    def __init__(self, path):
        self.s = socket.socket(socket.AF_UNIX)
        self.s.connect(path)
        self.f = self.s.makefile("rw")
        json.loads(self.f.readline())  # greeting
        self.cmd("qmp_capabilities")

    def cmd(self, name, **args):
        self.f.write(json.dumps({"execute": name, "arguments": args}) + "\n")
        self.f.flush()
        while True:
            msg = json.loads(self.f.readline())
            if "return" in msg:
                return msg["return"]
            if "error" in msg:
                raise RuntimeError(msg["error"])

    def combo(self, keys):
        self.cmd("send-key", keys=[{"type": "qcode", "data": k} for k in keys], **{"hold-time": 60})
        time.sleep(0.12)


def key_for(ch):
    if ch.isalpha():
        return ["shift", ch.lower()] if ch.isupper() else [ch]
    if ch.isdigit():
        return [ch]
    if ch in PLAIN:
        return [PLAIN[ch]]
    if ch in SHIFTED:
        return ["shift", SHIFTED[ch]]
    raise ValueError(f"cannot type {ch!r}")


def main():
    sock, action, *rest = sys.argv[1:]
    q = QMP(sock)
    if action == "shot":
        # QEMU runs in boot-qemu.sh's container, where RUNDIR is /run-dir:
        # a file next to the socket is written through that mount.
        import os
        out = os.path.abspath(rest[0])
        if os.path.dirname(out) == os.path.dirname(os.path.abspath(sock)):
            out = "/run-dir/" + os.path.basename(out)
        q.cmd("screendump", filename=out, format="png")
    elif action == "keys":
        for k in rest:
            q.combo(k.split("+"))
    elif action == "type":
        for ch in " ".join(rest):
            q.combo(key_for(ch))
    elif action == "quit":
        q.cmd("quit")
    else:
        sys.exit(f"unknown action {action}")


if __name__ == "__main__":
    main()
