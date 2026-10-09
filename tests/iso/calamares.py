#!/usr/bin/env python3
"""Calamares configuration checks for the Invictus installer (installer/calamares).

For both install paths (plain, advanced), assembled the way the live launcher
assembles /etc/calamares (common modules, then the path's own):
  - every YAML file parses;
  - every module in the sequence exists in Calamares 3.4.2 as we build it
    (pkgs/aur/calamares skip list applied), or is one of our instances,
    or is our diskcheck module, and has its config file;
  - module configs validate against the upstream schemas (tests/iso/calamares-schemas);
  - every shellprocess script names a job that exists in installer/jobs;
  - the design's decisions hold (users, partition, subvolumes, job order,
    choosers, branding).
Prints ok/FAIL lines; exit 1 on any failure.
"""
import os
import re
import sys

import yaml

try:
    import jsonschema
except ImportError:  # pragma: no cover
    jsonschema = None

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
CAL = os.path.join(REPO, "installer", "calamares")
SCHEMAS = os.path.join(HERE, "calamares-schemas")

# src/modules of the Calamares 3.4.2 release tarball.
CALAMARES_MODULES = set("""
bootloader contextualprocess displaymanager dracut dracutlukscfg dummycpp dummyprocess
dummypython finished finishedq fsresizer fstab grubcfg hostinfo hwclock initcpio initcpiocfg
initramfs initramfscfg interactiveterminal keyboard keyboardq license locale localecfg localeq
luksbootkeyfile luksopenswaphookcfg machineid mkinitfs mount netinstall networkcfg notesqml oemid
openrcdmcryptcfg packagechooser packagechooserq packages partition plasmalnf plymouthcfg
preservefiles rawfs removeuser services-openrc services-systemd shellprocess summary summaryq
tracking umount unpackfs unpackfsc users usersq welcome welcomeq zfs zfshostid
""".split())
OUR_MODULES = {"diskcheck", "invictusextras"}
# Modules that need no config file.
NO_CONFIG_OK = {"localecfg", "networkcfg", "hwclock", "umount", "summary", "invictusextras"}
EXTRAS_LIST = os.path.join(REPO, "scripts", "lib", "extras.list")
EXTRAS_MODULE = os.path.join(REPO, "installer", "modules", "invictusextras")

passed = 0
failed = 0


def check(name, cond, detail=""):
    global passed, failed
    if cond:
        print(f"ok    {name}")
        passed += 1
    else:
        print(f"FAIL  {name}" + (f": {detail}" if detail else ""))
        failed += 1


def load(path):
    with open(path) as f:
        return yaml.safe_load(f)


def skipped_modules():
    text = open(os.path.join(REPO, "pkgs", "aur", "calamares", "PKGBUILD")).read()
    m = re.search(r"_skip_modules=\(\s*(.*?)\)", text, re.S)
    return set(m.group(1).split()) if m else set()


def assemble(variant):
    """Same merge as installer/live/invictus-install."""
    modules = {}
    for d in (os.path.join(CAL, "common", "modules"), os.path.join(CAL, variant, "modules")):
        for f in sorted(os.listdir(d)):
            if f.endswith(".conf"):
                modules[f[:-5]] = os.path.join(d, f)
    return load(os.path.join(CAL, variant, "settings.conf")), modules


def seq(settings, kind):
    out = []
    for step in settings["sequence"]:
        out += step.get(kind, [])
    return out


def extras_list():
    """scripts/lib/extras.list as {package: how}."""
    out = {}
    for line in open(EXTRAS_LIST):
        line = line.strip()
        if line and not line.startswith("#"):
            name, how = line.split(None, 1)
            out[name] = how
    return out


def group_packages(groups):
    for g in groups:
        for p in g.get("packages", []):
            yield p if isinstance(p, str) else p["name"]
        yield from group_packages(g.get("subgroups", []))


def check_extras():
    """The Extras pages (one per path), the extras list and our job module agree."""
    listed = extras_list()
    on_page = sorted(n for n, how in listed.items() if how.startswith("page"))
    check("extras: the only automatic-only extra is NVIDIA firmware",
          sorted(n for n, how in listed.items() if not how.startswith("page")) == ["linux-firmware-nvidia"]
          and listed["linux-firmware-nvidia"].startswith("auto"))
    check("common: no shared Extras page (each path has its own)",
          not os.path.exists(os.path.join(CAL, "common", "modules", "netinstall.conf")))
    pages = {}
    for v in ("plain", "advanced"):
        ni = load(os.path.join(CAL, v, "modules", "netinstall.conf"))
        pages[v] = ni
        groups = ni["groups"]
        page = sorted(set(group_packages(groups)))
        check(f"{v} extras: the page draws from its own config, nothing downloaded", ni["groupsUrl"] == "local")
        check(f"{v} extras: the page may be left with nothing ticked", ni["required"] is False)
        check(f"{v} extras: every package on the page is in scripts/lib/extras.list as 'page'",
              all(p in on_page for p in page), str(page))
        check(f"{v} extras: no group or subgroup is critical (a missing extra never stops the install)",
              all(not g.get("critical", False) for g in groups for g in [g] + g.get("subgroups", [])))
        # Venus 2026-10-01: packages sit in one hidden, selected subgroup per
        # group, so no expand arrow shows a package name.
        check(f"{v} extras: each group shows no package (its packages are in one hidden, selected subgroup)",
              all("packages" not in g and len(g.get("subgroups", [])) == 1
                  and g["subgroups"][0].get("hidden") is True and g["subgroups"][0].get("selected") is True
                  and not g["subgroups"][0].get("subgroups") for g in groups), str([g["name"] for g in groups]))
        selected = [g["name"] for g in groups if g.get("selected")]
        check(f"{v} extras: only Documents is ticked by default", selected == ["Documents"], str(selected))
        by = {g["name"]: sorted(group_packages([g])) for g in groups}
        check(f"{v} extras: Documents installs invictus-office", by.get("Documents") == ["invictus-office"])
        check(f"{v} extras: Games is offered", by.get("Games") == ["invictus-gaming"])
        check(f"{v} extras: CJK fonts are offered", by.get("Chinese, Japanese and Korean text") == ["noto-fonts-cjk"])
        check(f"{v} extras: no AI set on the page (design-no-ai.md N5)",
              not ({"invictus-cicero", "invictus-voice", "claude-code"} & set(page)))
        title = ni["label"]["title"]
        # Calamares 3.4.2 page_netinst.ui: the title label does not wrap.
        check(f"{v} extras: the title says it needs internet, on one line (under 100 characters)",
              "online" in title and "\n" not in title and len(title) < 100, title)
        check(f"{v} extras: short descriptions (the column sizes to its contents)",
              all(len(g["description"]) <= 72 for g in groups), str([len(g["description"]) for g in groups]))
        check(f"{v} extras: plain words, no em-dash", "\u2014" not in yaml.safe_dump(ni, allow_unicode=True))
    adv = {g["name"]: g for g in pages["advanced"]["groups"]}
    pla = {g["name"]: g for g in pages["plain"]["groups"]}
    check("advanced extras: Programming is offered", sorted(group_packages([adv.get("Programming", {})])) == ["invictus-dev"])
    check("plain extras: no Programming (friends; Venus 2026-10-01)", "Programming" not in pla)
    check("extras: every page entry of extras.list is on the Advanced page",
          sorted(set(group_packages(pages["advanced"]["groups"]))) == on_page)
    check("extras: the plain page is the Advanced page less Programming, in the same order",
          list(pla) == [n for n in adv if n != "Programming"])
    check("extras: shared groups match (Games may name fewer tools on the plain path)",
          all(pla[n] == adv[n] for n in pla if n != "Games")
          and {k: v for k, v in pla["Games"].items() if k != "description"}
          == {k: v for k, v in adv["Games"].items() if k != "description"})
    check("extras: both paths use the same title", pages["plain"]["label"] == pages["advanced"]["label"])

    desc = load(os.path.join(EXTRAS_MODULE, "module.desc"))
    check("extras module: a Python job named invictusextras with no config",
          desc == {"type": "job", "name": "invictusextras", "interface": "python", "script": "main.py", "noconfig": True},
          str(desc))
    check_extras_module()


def check_extras_module():
    """installer/modules/invictusextras/main.py with a stand-in libcalamares."""
    import importlib.util
    import tempfile
    import types

    sys.dont_write_bytecode = True  # no __pycache__ next to the module
    fake = types.ModuleType("libcalamares")
    store = {}
    fake.globalstorage = types.SimpleNamespace(value=lambda k: store.get(k))
    fake.utils = types.SimpleNamespace(debug=lambda *a: None, warning=lambda *a: None)
    sys.modules["libcalamares"] = fake
    spec = importlib.util.spec_from_file_location("invictusextras_main", os.path.join(EXTRAS_MODULE, "main.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    ops = [
        {"source": "packagechooser@flavor", "install": ["not-this"]},
        {"source": "netinstall@netinstall", "install": ["a"], "try_install": ["invictus-office", {"package": "b", "pre-script": "x"}, "a"]},
    ]
    check("extras module: reads netinstall's install and try_install, in order, once each",
          mod.chosen(ops) == ["a", "invictus-office", "b"], str(mod.chosen(ops)))
    check("extras module: nothing ticked or no operations is an empty list",
          mod.chosen(None) == [] and mod.chosen([{"source": "netinstall@netinstall"}]) == [])

    with tempfile.TemporaryDirectory() as d:
        log = os.path.join(d, "args")
        job = os.path.join(d, "extras.sh")
        with open(job, "w") as f:
            f.write('#!/bin/sh\nprintf "%s\\n" "$@" > "' + log + '"\nexit "${FAKE_RC:-0}"\n')
        os.chmod(job, 0o755)
        mod.JOB = job
        store.update({"rootMountPoint": "/tmp/calamares-root-x", "packageOperations": ops})
        r = mod.run()
        args = open(log).read().split("\n")[:-1]
        check("extras module: runs the job with the root and the names as separate arguments",
              r is None and args == ["/tmp/calamares-root-x", "a", "invictus-office", "b"], str(args))
        store["packageOperations"] = [{"source": "netinstall@netinstall", "try_install": ["x; touch " + os.path.join(d, "pwned")]}]
        mod.run()
        check("extras module: a name is never run through a shell", not os.path.exists(os.path.join(d, "pwned")))
        os.environ["FAKE_RC"] = "1"
        r = mod.run()
        del os.environ["FAKE_RC"]
        check("extras module: a failing job fails the step with a message", isinstance(r, tuple) and len(r) == 2)
        store["packageOperations"] = [{"source": "netinstall@netinstall", "try_install": ["invictus-office"]}]
        store["locale"] = "ja-JP"
        mod.run()
        args = open(log).read().split("\n")[:-1]
        check("extras module: Japanese adds the CJK fonts though their box was not ticked",
              args == ["/tmp/calamares-root-x", "invictus-office", "noto-fonts-cjk"], str(args))
        store["locale"] = "en-GB"
        store["localeConf"] = {"LANG": "zh_TW.UTF-8"}
        check("extras module: Chinese in LANG counts too", mod.needs_cjk(store["locale"], store["localeConf"]))
        store["localeConf"] = {"LANG": "en_GB.UTF-8"}
        mod.run()
        args = open(log).read().split("\n")[:-1]
        check("extras module: English adds no fonts", args == ["/tmp/calamares-root-x", "invictus-office"], str(args))
        store["locale"] = "ko-KR"
        store["packageOperations"] = [{"source": "netinstall@netinstall", "try_install": ["noto-fonts-cjk"]}]
        mod.run()
        args = open(log).read().split("\n")[:-1]
        check("extras module: ticked and Korean names the fonts once", args == ["/tmp/calamares-root-x", "noto-fonts-cjk"], str(args))
        check("extras module: no language, no fonts", not mod.needs_cjk(None, None))
        store["rootMountPoint"] = None
        check("extras module: no root mount point fails the step", isinstance(mod.run(), tuple))


def main():
    skip = skipped_modules()
    check("Calamares build: the modules we use are not skipped",
          not ({"packagechooser", "netinstall", "shellprocess", "unpackfs", "initcpiocfg", "mount", "users", "partition"} & skip),
          str(skip))

    # Every YAML file parses.
    for dirpath, _, files in os.walk(CAL):
        for f in files:
            if f.endswith(".conf"):
                p = os.path.join(dirpath, f)
                try:
                    load(p)
                    ok = True
                    err = ""
                except yaml.YAMLError as e:
                    ok, err = False, str(e)
                check(f"YAML parses: {os.path.relpath(p, REPO)}", ok, err)
    for p in (os.path.join(REPO, "installer/branding/invictus/branding.desc"),):
        check(f"YAML parses: {os.path.relpath(p, REPO)}", isinstance(load(p), dict))

    for variant in ("plain", "advanced"):
        settings, modules = assemble(variant)
        v = variant
        instances = {i["id"]: i for i in settings.get("instances", [])}
        for i in instances.values():
            check(f"{v}: instance {i['id']} config file exists", i["config"][:-5] in modules, i["config"])
            check(f"{v}: instance {i['id']} module exists", i["module"] in CALAMARES_MODULES - skip)

        show, exe = seq(settings, "show"), seq(settings, "exec")
        for name in show + exe:
            if "@" in name:
                module, iid = name.split("@", 1)
                check(f"{v}: {name} is a declared instance", iid in instances and instances[iid]["module"] == module)
                check(f"{v}: {name} has a config", name in modules)
            else:
                known = name in (CALAMARES_MODULES - skip) or name in OUR_MODULES
                check(f"{v}: module {name} exists in our Calamares build", known)
                check(f"{v}: module {name} has a config (or needs none)", name in modules or name in NO_CONFIG_OK)

        # Schemas.
        if jsonschema is None:
            check(f"{v}: jsonschema installed (needed for schema checks)", False)
        else:
            for name, path in sorted(modules.items()):
                module = name.split("@", 1)[0]
                schema_path = os.path.join(SCHEMAS, f"{module}.schema.yaml")
                if not os.path.exists(schema_path):
                    continue
                schema = load(schema_path)
                try:
                    jsonschema.validate(load(path), schema)
                    err = ""
                except jsonschema.ValidationError as e:
                    err = e.message
                check(f"{v}: {name}.conf matches the Calamares schema", not err, err)

        # Shellprocess scripts name real jobs.
        for name, path in modules.items():
            if not name.startswith("shellprocess@"):
                continue
            cfg = load(path)
            check(f"{v}: {name} runs on the live system (dontChroot)", cfg.get("dontChroot") is True)
            for cmd in cfg["script"]:
                cmd = cmd["command"] if isinstance(cmd, dict) else cmd
                m = re.match(r"-?(/usr/lib/invictus/installer/(\S+\.sh))\s", cmd)
                check(f"{v}: {name} calls an installer job", bool(m), cmd)
                if m:
                    check(f"{v}: {name}: installer/jobs/{m.group(2)} exists",
                          os.path.isfile(os.path.join(REPO, "installer", "jobs", m.group(2))))
                if name == "shellprocess@invictus-sourcecheck":
                    # Runs before partition: no target root exists yet.
                    check(f"{v}: {name} checks unpackfs' source",
                          cmd.split()[1:] == [s["source"] for s in load(modules["unpackfs"])["unpack"]], cmd)
                else:
                    check(f"{v}: {name} passes the target root", "${ROOT}" in cmd, cmd)

        # --- design decisions -------------------------------------------------------
        users = load(modules["users"])
        groups = [g if isinstance(g, str) else g["name"] for g in users["defaultGroups"]]
        check(f"{v}: the person is an admin (wheel, DS1)", "wheel" in groups and users["sudoersGroup"] == "wheel")
        check(f"{v}: kvm group for rootless podman", "kvm" in groups)
        check(f"{v}: no root password is asked (root stays locked)", users["setRootPassword"] is False)
        check(f"{v}: no autologin", users["doAutologin"] is False)
        check(f"{v}: the live user's name cannot be taken", "liber" in users["user"]["forbidden_names"])

        part = load(modules["partition"])
        check(f"{v}: ESP at /boot, 4 GiB recommended (limine-snapper-sync)",
              part["efi"]["mountPoint"] == "/boot" and part["efi"]["recommendedSize"] == "4GiB")
        check(f"{v}: btrfs only", part["defaultFileSystemType"] == "btrfs" and part["availableFileSystemTypes"] == ["btrfs"])
        check(f"{v}: erase is the first choice", part["initialPartitioningChoice"] == "erase")
        check(f"{v}: swap is a file or none", set(part["userSwapChoices"]) == {"none", "file"})
        check(f"{v}: a Ventoy stick is never offered or closed", "ventoy" in part["essentialMounts"])
        if v == "plain":
            check("plain: no manual partitioning", part["allowManualPartitioning"] is False)
            check("plain: no encryption (DS8)", part["enableLuksAutomatedPartitioning"] is False)
            check("plain: hostname field hidden", users["hostname"]["location"] == "None")
        else:
            check("advanced: manual partitioning offered", part["allowManualPartitioning"] is True)
            check("advanced: encryption offered (D6)", part["enableLuksAutomatedPartitioning"] is True)
            check("advanced: LUKS2", part.get("luksGeneration") == "luks2")

        mount = load(modules["mount"])
        subs = [(s["mountPoint"], s["subvolume"]) for s in mount["btrfsSubvolumes"]]
        want = {("/", "/@"), ("/home", "/@home"), ("/var/log", "/@log"), ("/var/cache", "/@cache"),
                ("/var/cache/pacman/pkg", "/@pkg"), ("/.snapshots", "/@snapshots"), ("/var/lib/invictus/vm", "/@vm"),
                ("/home/.snapshots", "/@home-snapshots")}
        check(f"{v}: subvolumes are the design's (2.2, and @home-snapshots from design-simple-mode 12.2)",
              set(subs) == want, str(subs))
        pos = {mp: i for i, (mp, _) in enumerate(subs)}
        check(f"{v}: every parent mount point is listed before its children",
              all(pos[p] < pos[c] for p in pos for c in pos if c != p and c.startswith(p.rstrip("/") + "/")))
        check(f"{v}: swap subvolume @swap", mount["btrfsSwapSubvol"] == "/@swap")
        bt = [o for o in mount["mountOptions"] if o["filesystem"] == "btrfs"][0]["options"]
        check(f"{v}: btrfs mounted noatime, zstd:1", "noatime" in bt and "compress=zstd:1" in bt)

        initc = load(modules["initcpiocfg"])
        check(f"{v}: systemd hooks with sd-btrfs-overlayfs", initc["useSystemdHook"] is True
              and initc["hooks"]["append"] == ["sd-btrfs-overlayfs"])

        unp = load(modules["unpackfs"])["unpack"][0]
        check(f"{v}: unpacks the ISO's squashfs", unp["source"] == "/run/archiso/bootmnt/arch/x86_64/airootfs.sfs"
              and unp["sourcefs"] == "squashfs")

        units = {u["name"]: u for u in load(modules["services-systemd"])["units"]}
        for u in ("NetworkManager.service", "bluetooth.service", "sddm.service", "power-profiles-daemon.service",
                  "cups.socket", "avahi-daemon.service", "paccache.timer"):
            check(f"{v}: {u} enabled (docs/packages.md)", u in units and units[u]["action"] == "enable")
        check(f"{v}: sshd not enabled", "sshd.service" not in units or units["sshd.service"]["action"] != "enable")

        # Order of the exec phase.
        def at(n):
            return exe.index(n) if n in exe else -1
        check(f"{v}: no stock bootloader/initcpio/grub modules", not ({"bootloader", "initcpio", "grubcfg", "initramfs"} & set(exe)))
        check(f"{v}: cleanup after unpackfs and machineid, before users",
              at("unpackfs") < at("machineid") < at("shellprocess@invictus-cleanup") < at("users"))
        check(f"{v}: settings after users", at("users") < at("shellprocess@invictus-settings"))
        check(f"{v}: initcpiocfg before the bootloader job", at("initcpiocfg") < at("shellprocess@invictus-bootloader"))
        check(f"{v}: bootloader before snapper", at("shellprocess@invictus-bootloader") < at("shellprocess@invictus-snapper"))
        check(f"{v}: fstab before snapper (it needs the /.snapshots line)", at("fstab") < at("shellprocess@invictus-snapper"))
        check(f"{v}: umount last", exe[-1] == "umount")
        check(f"{v}: the source check runs first, before partition writes anything (note 60)",
              exe[0] == "shellprocess@invictus-sourcecheck" and at("partition") == 1)
        steps = settings["sequence"]
        first_show = steps[0].get("show", [])
        check(f"{v}: show, exec, show (the finished page)", len(steps) == 3 and "exec" in steps[1]
              and steps[2] == {"show": ["finished"]})
        check(f"{v}: the tick box is the last page before the install", first_show[-1:] == ["diskcheck"])
        check(f"{v}: branding is invictus", settings["branding"] == "invictus")

        # The Extras page (netinstall) and the job that installs its ticks.
        check(f"{v}: the Extras page is shown before the account and disk pages",
              "netinstall" in first_show and first_show.index("netinstall") < first_show.index("users"))
        check(f"{v}: the extras job runs after the bootloader job and before snapper",
              at("shellprocess@invictus-bootloader") < at("invictusextras") < at("shellprocess@invictus-snapper"))
        check(f"{v}: no stock packages module (the extras job installs, and survives no internet)",
              "packages" not in exe)

        st = load(modules["shellprocess@invictus-settings"])["script"][0]
        if v == "plain":
            check("plain: writes Atrium + Custodia (SM24)", st.endswith("${USER} atrium custodia --hostname-from-user"), st)
        else:
            check("advanced: writes the chosen flavor and guard rails",
                  "${gs[packagechooser_flavor]} ${gs[packagechooser_guardrails]}" in st, st)
            fl = load(modules["packagechooser@flavor"])
            gr = load(modules["packagechooser@guardrails"])
            check("advanced: flavor choices atrium/tessera, default atrium",
                  [i["id"] for i in fl["items"]] == ["atrium", "tessera"] and fl["default"] == "atrium" and fl["mode"] == "required")
            check("advanced: guard rails custodia/libertas, default custodia",
                  [i["id"] for i in gr["items"]] == ["custodia", "libertas"] and gr["default"] == "custodia" and gr["mode"] == "required")
            for i in fl["items"] + gr["items"]:
                art = os.path.join(REPO, "installer/branding/invictus/art", i["screenshot"].replace(".png", ".svg"))
                check(f"advanced: picture for {i['id']} exists", os.path.isfile(art))

    check_extras()

    # Branding.
    b = load(os.path.join(REPO, "installer/branding/invictus/branding.desc"))
    check("branding: never uploads logs anywhere", b["uploadServer"]["type"] == "none")
    check("branding: product name Invictus", b["strings"]["productName"] == "Invictus")
    values = yaml.safe_dump(b)
    check("branding: no Arch name in any value", not re.search(r"\barch\b", values, re.I))
    check("branding: Dusk sidebar", b["style"]["SidebarBackground"] == "#14120F" and b["style"]["SidebarTextCurrent"] == "#E0A64B")

    qss = open(os.path.join(REPO, "installer/branding/invictus/stylesheet.qss")).read()
    ind = re.search(r"QCheckBox::indicator, QRadioButton::indicator \{([^}]*)\}", qss)
    check("stylesheet: an unticked box is drawn (indicator has a border and background)",
          bool(ind) and "border:" in ind.group(1) and "background-color:" in ind.group(1))
    check("stylesheet: a ticked box is drawn", "::indicator:checked" in qss)

    print()
    print(f"calamares: {passed} passed, {failed} failed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
