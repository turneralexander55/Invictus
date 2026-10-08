#!/usr/bin/env python3
"""Installed-disk boot test driver (tests/iso/disk-boot.sh starts QEMU).

    disk-boot.py RUNDIR --env DISK.ENV [--timeout SECONDS] [--sync-wait SECONDS]
                 [--no-snapshot-boot]

The disk image tests/iso/e2e-jobs.sh --keep leaves behind boots through its
own ESP: OVMF, limine (EFI/BOOT/BOOTX64.EFI), limine.conf's default entry.
The image's debug-shell.service gives a root shell on the guest's second
serial port (RUNDIR/shell.sock). DISK.ENV (key=value, written by e2e-jobs)
says what the boot must show: kernel (uname -r), kernel_pkgbase, root_uuid,
rails.

Fails when, on the first boot:
  - no root shell, or the boot does not finish, before the deadline;
  - the running kernel is not the image's CachyOS kernel, or /proc/cmdline
    is not the command line of limine.conf's entry for it (so limine's
    menu picked something else);
  - the default target is not reached (systemctl, systemd-analyze), or the
    display manager (the login screen) is not running;
  - / is not btrfs subvol=/@, or systemd-remount-fs.service did not run and
    stay active (fstab's options for / were not applied; build note 57);
  - the boot finished in any state but "running", any unit failed, a job is still queued, or PID 1 logged a timeout or a
    failed dependency (the boot smoke test's rules, guest_shell.BAD_JOURNAL);
  - snapper's root config has no "Fresh install" snapshot, or limine.conf
    has no limine-snapper-sync entry booting it (within --sync-wait s);
  - sshd runs or a socket of sshd's own units is listening;
  - `invictus-sys guardrails status` does not show the image's rails, or
    `invictus-sys guardrails check` says the derived files are wrong.
Then, unless --no-snapshot-boot, it makes the Fresh install entry limine's
default (all menu folders open, default_entry pointing at it), reboots,
and fails unless that boot runs from the snapshot, reaches
multi-user.target and finishes "running", with no failed unit, queued job
or bad PID 1 journal line: a rollback must boot as cleanly as the system
it rolls back to (CI run 37847290984 booted it "degraded", with
systemd-remount-fs failed on the overlay root).

Writes RUNDIR/report.txt, journal.txt (first boot), journal-snapshot.txt,
limine.conf and screen.png.
"""
import argparse
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))

sys.dont_write_bytecode = True  # no __pycache__ in the checkout
sys.path.insert(0, HERE)
from guest_shell import BAD_JOURNAL, Shell, sshd_socket_lines, wait_root_shell  # noqa: E402

LIMINE_CONF = "/boot/limine.conf"
ENTRY = re.compile(r"^(\s*)(/+)(\+?)(.*?)\s*$")
OPTION = re.compile(r"^\s*([A-Za-z_]+)\s*:\s*(.*?)\s*$")
# limine-snapper-sync's own pattern for a snapshot command line
# (Utility.java: "subvol=.*?/([0-9]+)/snapshot"), anchored to our layout.
SNAP_SUBVOL = re.compile(r"(?:^|[ ,=])subvol=/?@snapshots/(\d+)/snapshot(?=[ ,]|$)")


# ---- limine.conf -------------------------------------------------------------------------
def parse_limine(text):
    """Entries in file order: dicts with line (0-based), depth, expanded, name, options."""
    entries = []
    for i, line in enumerate(text.splitlines()):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = ENTRY.match(line)
        if m:
            entries.append({"line": i, "depth": len(m.group(2)), "expanded": m.group(3) == "+",
                            "name": m.group(4), "options": {}})
            continue
        m = OPTION.match(line)
        if m and entries:
            entries[-1]["options"].setdefault(m.group(1).lower(), m.group(2))
    for n, e in enumerate(entries):
        e["dir"] = n + 1 < len(entries) and entries[n + 1]["depth"] > e["depth"]
    return entries


def cmdline_of(e):
    o = e["options"]
    return o.get("cmdline", o.get("kernel_cmdline", ""))


def kernel_path_of(e):
    o = e["options"]
    return o.get("path", o.get("kernel_path", ""))


def snapshot_number(e):
    m = SNAP_SUBVOL.search(cmdline_of(e))
    return int(m.group(1)) if m else None


def main_entry(entries, pkgbase):
    """The first boot entry for PKGBASE's kernel that does not boot a snapshot."""
    for e in entries:
        if not e["dir"] and f"/{pkgbase}/vmlinuz" in kernel_path_of(e) and snapshot_number(e) is None:
            return e
    return None


def snapshot_entry(entries, number):
    """The first boot entry whose command line boots snapshot NUMBER."""
    for e in entries:
        if not e["dir"] and kernel_path_of(e) and snapshot_number(e) == number:
            return e
    return None


def default_entry_sed(text, target):
    """sed arguments that open every menu folder and make TARGET (an entry
    from parse_limine(TEXT)) limine's default_entry. With every folder open,
    the 1-based place of an entry in the file is its place in the menu,
    however limine counts closed folders. Returns (index, [sed args])."""
    entries = parse_limine(text)
    index = next(n + 1 for n, e in enumerate(entries) if e["line"] == target["line"])
    args = []
    for e in entries:
        if e["dir"] and not e["expanded"]:
            # The first "/" not followed by "/" or "+" is the last slash.
            args += ["-e", f"{e['line'] + 1}s|/\\([^/+]\\)|/+\\1|"]
    lines = text.splitlines()
    have = [n for n, ln in enumerate(lines) if re.match(r"^\s*default_entry\s*:", ln, re.I)]
    if have:
        args += ["-e", f"{have[0] + 1}s|.*|default_entry: {index}|"]
    else:
        args += ["-e", f"1i default_entry: {index}"]
    return index, args


def same_cmdline(running, entry):
    """/proc/cmdline is the entry's command line; a loader may add BOOT_IMAGE= or initrd=."""
    extra = ("BOOT_IMAGE=", "initrd=")
    return [t for t in running.split() if not t.startswith(extra)] == entry.split()


def shell_quote(s):
    return "'" + s.replace("'", "'\\''") + "'"


# ---- the run -----------------------------------------------------------------------------
def read_env(path):
    env = {}
    with open(path) as f:
        for line in f:
            k, sep, v = line.strip().partition("=")
            if sep:
                env[k] = v
    return env


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--env", required=True)
    ap.add_argument("--timeout", type=int, default=600, help="seconds per boot")
    ap.add_argument("--sync-wait", type=int, default=120,
                    help="seconds to wait for limine-snapper-sync's entry")
    ap.add_argument("--no-snapshot-boot", action="store_true")
    a = ap.parse_args()
    env = read_env(a.env)
    for k in ("kernel", "kernel_pkgbase", "root_uuid", "rails"):
        if not env.get(k):
            sys.exit(f"disk-boot: {a.env} has no {k}=")
    t0 = time.monotonic()
    run = a.rundir
    problems, notes, report = [], [], []

    def say(msg):
        msg = f"[{time.monotonic() - t0:6.0f}s] {msg}"
        print(msg, flush=True)
        report.append(msg)

    def save(name, text):
        with open(os.path.join(run, name), "w") as f:
            f.write(text)

    def finish():
        try:
            subprocess.run([sys.executable, os.path.join(HERE, "qmp.py"), os.path.join(run, "qmp.sock"),
                            "shot", os.path.join(run, "screen.png")], timeout=30, check=False)
        except Exception:  # a screenshot is a nice-to-have
            pass
        for n in notes:
            say(f"note  {n}")
        for p in problems:
            say(f"FAIL  {p}")
        say("disk boot: " + ("FAILED" if problems else "passed"))
        save("report.txt", "\n".join(report) + "\n")
        sys.exit(1 if problems else 0)

    def out(cmd, timeout=30):
        r = sh.run(cmd, timeout)
        return None if r is None else r[1]

    def boot_health(label, first):
        """Failed units, queued jobs and PID 1's journal lines are problems on either boot."""
        r = sh.run("systemctl --failed --plain --no-legend --full", 30)
        if r and r[1].strip():
            problems.append(f"{label}: failed units:\n" + r[1].rstrip())
        r = sh.run("systemctl list-jobs --no-legend --full", 30)
        if r and r[1].strip() and "No jobs" not in r[1]:
            problems.append(f"{label}: jobs still queued after boot:\n" + r[1].rstrip())
        r = sh.run("journalctl -b --no-pager -o short-monotonic", 90)
        if r:
            save("journal.txt" if first else "journal-snapshot.txt", r[1])
            bad = [ln for ln in r[1].splitlines() if BAD_JOURNAL.search(ln)]
            if bad:
                problems.append(f"{label}: journal:\n" + "\n".join(bad[:40]))

    def wait_boot(label, deadline):
        r = sh.run("systemctl is-system-running --wait", deadline - time.monotonic())
        if r is None:
            jobs = out("systemctl list-jobs --no-legend --full") or "?"
            problems.append(f"{label}: boot not finished within {a.timeout} s; jobs still queued:\n{jobs}")
            return False
        state = r[1].strip()
        say(f"{label}: boot finished: {state}")
        if state != "running":
            problems.append(f"{label}: the boot finished {state or '?'}, not running")
        return True

    def remount_fs():
        """systemd-remount-fs.service's ActiveState and Result."""
        kv = dict(ln.split("=", 1) for ln in (out("systemctl show -p ActiveState -p Result "
                                                  "systemd-remount-fs.service") or "").splitlines() if "=" in ln)
        return kv.get("ActiveState", "?"), kv.get("Result", "?")

    # ---- first boot: the normal entry ----------------------------------------------------
    deadline = t0 + a.timeout
    try:
        sh = Shell(os.path.join(run, "shell.sock"), deadline)
    except TimeoutError as e:
        problems.append(str(e))
        finish()
    try:
        if not wait_root_shell(sh, deadline):
            problems.append(f"no root shell on the second serial port within {a.timeout} s (limine, the "
                            "kernel or the initramfs did not get to systemd; see screen.png)")
            finish()
        say("root shell up")
        wait_boot("first boot", deadline)
        sh.deadline = max(sh.deadline, time.monotonic() + 300 + a.sync_wait)
        boot_id = (out("cat /proc/sys/kernel/random/boot_id") or "").strip()

        # The kernel, and the limine entry it came from.
        uname = (out("uname -r") or "").strip()
        if uname != env["kernel"] or "cachyos" not in uname:
            problems.append(f"running kernel {uname or '?'}, expected the image's CachyOS kernel {env['kernel']}")
        else:
            say(f"kernel {uname}")
        cmdline = (out("cat /proc/cmdline") or "").strip()
        conf = out(f"cat {LIMINE_CONF}") or ""
        entries = parse_limine(conf)
        main_e = main_entry(entries, env["kernel_pkgbase"])
        if main_e is None:
            problems.append(f"{LIMINE_CONF} has no {env['kernel_pkgbase']} entry")
        elif not same_cmdline(cmdline, cmdline_of(main_e)):
            problems.append(f"/proc/cmdline is not the {env['kernel_pkgbase']} entry's command line (limine "
                            f"booted something else):\n  running: {cmdline}\n  entry:   {cmdline_of(main_e)}")
        else:
            say(f"limine booted the //{main_e['name']} entry: {cmdline}")
        if f"root=UUID={env['root_uuid']}" not in cmdline.split():
            problems.append(f"/proc/cmdline does not name the image's root (root=UUID={env['root_uuid']}): {cmdline}")
        loader = (out("tr -d '\\000' < /sys/firmware/efi/efivars/LoaderInfo-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f "
                      "2>/dev/null") or "").strip()
        say(f"LoaderInfo: {loader or '(not set)'}")

        # The default target and the login screen.
        target = (out("systemctl get-default") or "").strip()
        state = (out(f"systemctl is-active {target or 'default.target'}") or "").strip()
        analyze = out("systemd-analyze time") or ""
        if not target or state != "active" or f"{target} reached after" not in analyze:
            problems.append(f"default target {target or '?'} not reached (is-active: {state or '?'}); "
                            f"systemd-analyze time:\n{analyze.rstrip()}")
        else:
            say(f"$ systemd-analyze time\n{analyze.rstrip()}")
        dm = (out("systemctl is-active display-manager.service") or "").strip()
        if dm != "active":
            problems.append(f"the display manager (login screen) is not running: display-manager.service {dm or '?'}")
        # / from the kernel command line (rootflags=subvol=/@), then fstab's
        # options applied by systemd-remount-fs, which the snapshot-boot drop-in
        # (build note 57) must leave running on a normal boot.
        root = (out("findmnt -n -o FSTYPE,OPTIONS --mountpoint /") or "").split()
        if len(root) != 2 or root[0] != "btrfs" or "subvol=/@" not in root[1].split(","):
            problems.append(f"/ is not btrfs subvol=/@: {' '.join(root) or '?'}")
        else:
            say(f"/ is btrfs {root[1]}")
        rfs = remount_fs()
        if rfs != ("active", "success"):
            problems.append("systemd-remount-fs.service did not run on the normal boot (fstab's options for / not "
                            f"applied): ActiveState={rfs[0]} Result={rfs[1]}")
        boot_health("first boot", True)

        # Snapper's first snapshot and limine-snapper-sync's entry for it.
        snaps = out("snapper --no-dbus -c root list") or ""
        fresh = next((int(m.group(1)) for ln in snaps.splitlines() if "Fresh install" in ln
                      for m in [re.match(r"\s*(\d+)\b", ln)] if m), None)
        if fresh is None:
            problems.append("snapper's root config has no \"Fresh install\" snapshot:\n" + snaps.rstrip())
        else:
            say(f"snapshot {fresh}: Fresh install")
            snap_e = None
            sync_end = time.monotonic() + a.sync_wait
            while True:
                snap_e = snapshot_entry(entries, fresh)
                if snap_e is not None or time.monotonic() > sync_end:
                    break
                time.sleep(5)
                conf = out(f"cat {LIMINE_CONF}") or conf
                entries = parse_limine(conf)
            if snap_e is None:
                state = (out("systemctl is-active limine-snapper-sync.service") or "").strip()
                problems.append(f"{LIMINE_CONF} has no limine-snapper-sync entry for snapshot {fresh} after "
                                f"{a.sync_wait} s (limine-snapper-sync.service: {state or '?'})")
            else:
                say(f"limine.conf boots snapshot {fresh} from //{snap_e['name']}")
        save("limine.conf", conf)

        # sshd off (design-simple-mode 1.3): no daemon, no socket of any kind.
        r = sh.run("systemctl list-sockets --all --no-legend --full", 30)
        if r is None:
            problems.append("could not list the system's sockets")
        elif sshd_socket_lines(r[1]):
            # sshd's own units only (guest_shell.SSHD_UNIT), not gpg-agent's
            # keyring ssh socket.
            problems.append("an ssh socket is listening:\n" + "\n".join(sshd_socket_lines(r[1])))
        sshd = (out("systemctl is-active sshd.service") or "").strip()
        if sshd in ("active", "activating", "reloading"):
            problems.append(f"sshd.service is {sshd}")
        listen = out("ss -Hlp") or ""
        if any('"sshd' in ln for ln in listen.splitlines()):
            problems.append("sshd is listening:\n" + "\n".join(ln for ln in listen.splitlines() if '"sshd' in ln))

        # Custodia: the guard-rails file and the files derived from it.
        st = out("invictus-sys guardrails status") or ""
        kv = dict(ln.split("=", 1) for ln in st.splitlines() if "=" in ln)
        if kv.get("rails") != env["rails"] or kv.get("effective") != env["rails"]:
            problems.append(f"guard rails are not {env['rails']}: invictus-sys guardrails status says\n{st.rstrip()}")
        elif env["rails"] == "custodia" and kv.get("full-access") != "off":
            problems.append(f"Custodia with the assistant's full access {kv.get('full-access', '?')}")
        else:
            say(f"guard rails: {kv.get('rails')}, full-access {kv.get('full-access', '?')}")
        r = sh.run("invictus-sys guardrails check", 60)
        if r is None or r[0] != 0:
            problems.append("invictus-sys guardrails check: the derived files do not match the rails:\n"
                            + (r[1].rstrip() if r else "(no answer)"))

        for cmd in ("systemd-analyze blame --no-pager | head -n 15",):
            r = sh.run(cmd, 30)
            if r:
                say(f"$ {cmd}\n{r[1].rstrip()}")

        # ---- second boot: the snapshot entry ---------------------------------------------
        if a.no_snapshot_boot:
            notes.append("snapshot boot skipped (--no-snapshot-boot)")
            finish()
        if fresh is None or snap_e is None:
            problems.append("snapshot boot not tried: no snapshot entry to boot")
            finish()
        out("systemctl stop limine-snapper-sync.service")  # it rewrites limine.conf on changes
        conf = out(f"cat {LIMINE_CONF}") or conf
        entries = parse_limine(conf)
        snap_e = snapshot_entry(entries, fresh)
        if snap_e is None:
            problems.append(f"snapshot {fresh}'s entry left {LIMINE_CONF} while the test ran")
            finish()
        index, sed = default_entry_sed(conf, snap_e)
        r = sh.run("sed -i " + " ".join(shell_quote(x) for x in sed) + f" {LIMINE_CONF} && sync", 30)
        after = out(f"cat {LIMINE_CONF}") or ""
        if r is None or r[0] != 0 or f"default_entry: {index}" not in after.splitlines():
            problems.append(f"could not make entry {index} limine's default:\n" + (r[1] if r else "(no answer)"))
            finish()
        say(f"default_entry: {index} (snapshot {fresh}), every menu folder open; rebooting")
        sh.send("systemctl reboot")
        deadline = time.monotonic() + a.timeout
        sh.deadline = deadline
        new_id = boot_id
        while time.monotonic() < deadline:
            if wait_root_shell(sh, deadline):
                new_id = (out("cat /proc/sys/kernel/random/boot_id", 10) or boot_id).strip()
                if new_id and new_id != boot_id:
                    break
            time.sleep(2)
        if not new_id or new_id == boot_id:
            problems.append(f"the snapshot boot did not come up within {a.timeout} s (see screen.png)")
            finish()
        say("snapshot boot: root shell up")
        wait_boot("snapshot boot", deadline)
        sh.deadline = max(sh.deadline, time.monotonic() + 180)
        cmdline = (out("cat /proc/cmdline") or "").strip()
        if SNAP_SUBVOL.search(cmdline) is None or int(SNAP_SUBVOL.search(cmdline).group(1)) != fresh:
            problems.append(f"default_entry {index} did not boot snapshot {fresh}; /proc/cmdline: {cmdline}")
        else:
            say(f"snapshot boot: {cmdline}")
        mu = (out("systemctl is-active multi-user.target") or "").strip()
        if mu != "active":
            problems.append(f"the snapshot boot did not reach multi-user.target ({mu or '?'})")
        else:
            say("snapshot boot: multi-user.target reached")
        say("snapshot boot: / is " + (out("findmnt -n -o FSTYPE,SOURCE /") or "?").strip())
        say("snapshot boot: systemd-remount-fs.service ActiveState=%s Result=%s" % remount_fs())
        boot_health("snapshot boot", False)
    except ConnectionError as e:
        problems.append(str(e))
    finish()


if __name__ == "__main__":
    main()
