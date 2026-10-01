#!/usr/bin/env python3
"""invictusextras: hand the Extras page's ticks to the extras job.

The Extras page is Calamares' own netinstall module. It only records what
was ticked, as the global storage value "packageOperations" (a list of
maps). shellprocess cannot read that: it expands text and maps from
global storage, not lists (Calamares 3.4.2, CommandList.cpp). So this job
reads the list and runs /usr/lib/invictus/installer/extras.sh ROOT NAMES,
which does the work and decides what happens without internet
(installer/jobs/extras.sh).

One inference (Venus, 2026-10-01): when the language picked on the
Location page is Chinese, Japanese or Korean, the CJK fonts are added
whether or not their box was ticked. Without them that person's own
desktop shows empty boxes. netinstall cannot tick the box from the
language, so the job does it.
"""
import subprocess

import libcalamares

JOB = "/usr/lib/invictus/installer/extras.sh"


def pretty_name():
    return "Adding the extras you picked"


def chosen(operations):
    """Package names the netinstall page put in packageOperations, in order."""
    names = []
    for op in operations or []:
        if not isinstance(op, dict) or not str(op.get("source", "")).startswith("netinstall"):
            continue
        for key in ("install", "try_install"):
            for item in op.get(key) or []:
                name = item.get("package") if isinstance(item, dict) else item
                if isinstance(name, str) and name and name not in names:
                    names.append(name)
    return names


CJK_FONTS = "noto-fonts-cjk"
CJK_LANGUAGES = ("zh", "ja", "ko")


def needs_cjk(locale, locale_conf):
    """True when the chosen language is Chinese, Japanese or Korean.

    locale is the BCP 47 tag the locale page stores ("ja-JP"); locale_conf
    its map of LANG and LC_* values ("ja_JP.UTF-8"). Either may be missing.
    """
    tags = [locale] if isinstance(locale, str) else []
    if isinstance(locale_conf, dict):
        tags.append(locale_conf.get("LANG"))
    for tag in tags:
        if isinstance(tag, str) and tag.replace("_", "-").split("-")[0].split(".")[0].lower() in CJK_LANGUAGES:
            return True
    return False


def run():
    gs = libcalamares.globalstorage
    root = gs.value("rootMountPoint")
    if not root:
        return ("No target system", "The extras job has no root mount point.")
    names = chosen(gs.value("packageOperations"))
    if needs_cjk(gs.value("locale"), gs.value("localeConf")) and CJK_FONTS not in names:
        names.append(CJK_FONTS)
    libcalamares.utils.debug("invictusextras: picked {}".format(names or "nothing"))
    # A list of arguments, no shell. extras.sh checks every name against
    # the target's /usr/share/invictus/extras.list.
    proc = subprocess.run([JOB, root] + names, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          universal_newlines=True)
    for line in proc.stdout.splitlines():
        libcalamares.utils.debug(line)
    if proc.returncode != 0:
        return ("The extras could not be set up",
                "extras.sh stopped with code {}. The installer log has its output.".format(proc.returncode))
    return None
