#!/usr/bin/env python3
r"""Pack AchaeaRestock.lua plus the alias table below into a Mudlet package.

Produces two things next to this script:

  AchaeaRestock.xml       drag-and-drop installable, and committed to the repo
  AchaeaRestock.mpackage  the zip form Mudlet's package manager prefers

The shape is deliberate: real <Alias> elements inside one <AliasGroup> so they
can be read in Mudlet's Editor, and ALIASES as the single source of truth for
both the XML and the restock.COMMANDS table appended to the Lua, so the
in-game help cannot drift from what is installed.

There are no <Trigger> elements and no tempTrigger either. The rift arrives
over GMCP -- Mudlet asks for IRE.Rift in its own opening handshake -- so this
package never reads a line of game output. The only thing it sends is
IRE.Rift.Request.

Note that the heading alias enumerates the nine headings rather than taking
`^restock\s+(\S+)$`. Mudlet fires every alias that matches rather than the
first (AliasUnit::processDataStream loops the whole root list), so a catch-all
would fire *alongside* `restock diag` rather than being shadowed by it.
"""

from __future__ import annotations

import hashlib
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

HERE = Path(__file__).parent

# Where a recipient can get the Corresponding Source. GPL-3 asks that they be
# able to, and the .mpackage ships the *generated* .xml rather than the .lua and
# build.py that are the preferred form for making modifications -- so the
# package cannot serve as its own source, and has to say where the source is.
SOURCE_URL = "https://github.com/PrincessSiren/achaea-restock"
DOCS_URL = f"{SOURCE_URL}/tree/main/docs"

# What the package manager's globe button opens -- dlgPackageManager reads
# `helpURL` and nothing else. The repository root rather than docs/: someone
# clicking through from a package listing wants what it is and how to install
# it, which is the README, and the description already links docs/ by name.
HELP_URL = SOURCE_URL

# The date that goes into config.lua as `created`, which Mudlet's package
# repository requires and its validator greps for.
#
# A constant rather than today's date, because both build artefacts here are
# byte-reproducible: build twice with no source change and the .xml and the
# .mpackage are identical, which is what lets anyone rebuild a tag and check
# the digest against the one the release published. A wall clock in the
# archive would throw that away for a field nothing reads back. Move it when
# the version moves.
CREATED = "2026-09-18"
LUA = HERE / "AchaeaRestock.lua"
XML = HERE / "AchaeaRestock.xml"
MPACKAGE = HERE / "AchaeaRestock.mpackage"

PACKAGE_NAME = "AchaeaRestock"

# Mudlet's scmMudletXmlDefaultVersion (src/mudlet.h).
XML_VERSION = "1.001"

# (name, regex, lua, usage, help)
#
# Every argument-taking alias takes it as an optional trailing group where the
# argument is optional, because Mudlet hands an unmatched group over as ""
# rather than nil and the Lua treats both as "no argument" -- which is what
# lets `restock slack` report and `restock slack 20` set, on one alias.
ALIASES: list[tuple[str, str, str, str, str]] = [
    (
        "report",
        r"^restock$",
        "restock.report()",
        "restock",
        "what is below target, worst shortfall first",
    ),
    (
        "help",
        r"^restock\s+help$",
        "restock.help()",
        "restock help",
        "this command list",
    ),
    (
        "all",
        r"^restock\s+all$",
        "restock.listing()",
        "restock all",
        "everything in the rift, grouped the way RIFT groups it",
    ),
    (
        "heading",
        r"^restock\s+(herbs|minerals|elixirs|salves|inks|reagent"
        r"|ingredients|commodities|shipcomm)$",
        "restock.reportCategory(matches[2])",
        "restock <heading>",
        "one heading: what you hold, and what is short",
    ),
    (
        "targets",
        r"^restock\s+target$",
        "restock.targetList()",
        "restock target",
        "every target you have set",
    ),
    (
        "settarget",
        r"^restock\s+target\s+(.+?)\s+(\d+)$",
        "restock.setTarget(matches[2], matches[3])",
        "restock target <heading|item> <n>",
        "hold n of it; setting a target is what opts it into the report",
    ),
    (
        "forget",
        r"^restock\s+forget\s+(.+)$",
        "restock.forget(matches[2])",
        "restock forget <heading|item>",
        "drop a target again",
    ),
    (
        "slack",
        r"^restock\s+slack(?:\s+(\d+))?$",
        "restock.setSlack(matches[2])",
        "restock slack [n]",
        "how far below target still counts as stocked",
    ),
    (
        "refresh",
        r"^restock\s+refresh$",
        "restock.refresh()",
        "restock refresh",
        "ask the game for the whole rift again (IRE.Rift.Request)",
    ),
    (
        "diag",
        r"^restock\s+diag$",
        "restock.diag()",
        "restock diag",
        "build stamp, frames seen, and any held item with no heading",
    ),
]

XML_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE MudletPackage>
<MudletPackage version="{xml_version}">
    <ScriptPackage>
        <Script isActive="yes" isFolder="no">
            <name>{package}</name>
            <packageName>{package}</packageName>
            <script>{script}</script>
            <eventHandlerList />
        </Script>
    </ScriptPackage>
    <AliasPackage>
        <AliasGroup isActive="yes" isFolder="yes">
            <name>{package}</name>
            <script></script>
            <command></command>
            <packageName>{package}</packageName>
            <regex></regex>
{aliases}        </AliasGroup>
    </AliasPackage>
</MudletPackage>
"""

ALIAS_TEMPLATE = """            <Alias isActive="yes" isFolder="no">
                <name>{name}</name>
                <script>{script}</script>
                <command></command>
                <packageName>{package}</packageName>
                <regex>{regex}</regex>
            </Alias>
"""


def read_version(lua_source: str) -> str:
    for raw in lua_source.splitlines():
        line = raw.strip()
        if line.startswith("M.VERSION"):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    return "0.0.0"


def lua_quote(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def build_stamp(lua_source: str) -> str:
    """Short digest of everything that ends up in the package.

    A content hash rather than a timestamp, because the .xml is committed: two
    builds with no source change must be byte-identical. `restock diag`
    prints it back, which is the only reliable answer to "is Mudlet running
    what is on disk?" -- the version says what you expect whether or not you
    rebuilt.
    """
    material = lua_source + "\x00".join("\x00".join(row) for row in ALIASES)
    return hashlib.sha256(material.encode("utf-8")).hexdigest()[:8]


def commands_lua(lua_source: str) -> str:
    rows = "".join(
        f"    {{ usage = {lua_quote(usage)}, help = {lua_quote(help)} }},\n"
        for _name, _regex, _lua, usage, help in ALIASES
    )
    return (
        "\n-- Generated by build.py from its ALIASES table. Do not edit here.\n"
        f"restock.BUILD = {lua_quote(build_stamp(lua_source))}\n"
        f"restock.COMMANDS = {{\n{rows}}}\n"
    )


DESCRIPTION = f"""# AchaeaRestock

What to buy before you go out.

Reads your rift over GMCP, compares it against targets you set, and prints what
is short and how much of it to buy. It sends one thing, IRE.Rift.Request, and
triggers on nothing.

**Nothing ships with a target.** How much bloodroot you want is a preference
rather than a game fact, so setting one is what opts a heading or an item into
the report:

```
restock target herbs 500
restock target health 1500
restock
```

`restock all` prints the whole rift grouped the way RIFT groups it, and
`restock help` is the full command list.

Capacities come from HELP 7.14, so `restock` knows what the rift will not hold
more of -- with one hole, recorded rather than guessed: 7.14 never states a cap
for minerals.

Why it is built this way, and the captured game output the tables are read off,
are in the docs: {DOCS_URL}

Source and licence (GPL-3.0-or-later): {SOURCE_URL}"""


# The archive is built to be byte-identical anywhere, so that rebuilding a tag
# and comparing the digest is a check anyone can run. Two things had to give.
#
# The date. `writestr` with a plain string name takes `time.localtime()`, to
# the second, so two builds a second apart produced different archives -- easy
# to miss, because two builds inside the same second did not. 1980-01-01 is the
# earliest a zip can express, and nothing reads these back: Mudlet unzips into
# a profile directory and the dates there are the install's. `created` in
# config.lua is where a real date belongs.
#
# The compression. Deflate output is not defined by the format, it is whatever
# the linked zlib emits -- and Fedora's python links zlib-ng while an Ubuntu
# runner links stock zlib, so identical files gave different archives on the
# two machines. That is not a bug in either; there is no portable way to pin
# it. Storing the entries uncompressed takes the question away entirely, at
# 70KB against 22KB. Most of the difference is the GPL text, and the trade is
# worth it for a package whose whole claim is that you can check it yourself.
ZIP_EPOCH = (1980, 1, 1, 0, 0, 0)


def zip_entry(name: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, date_time=ZIP_EPOCH)
    info.compress_type = zipfile.ZIP_STORED
    # A ZipInfo built by hand carries no mode at all, which some extractors
    # read as 0000. Say 0644 rather than leave it to them.
    info.external_attr = 0o644 << 16
    return info


def config_lua(version: str) -> str:
    """The package metadata Mudlet reads back out of the archive.

    Host::readPackageInfo runs this file as Lua and keeps every global that is
    a string, so a key added here is a key Mudlet's package manager can show.
    mpackage, title, version, created, author and description are the six the
    Mudlet package repository's validator requires; helpURL is what the package
    manager's globe button opens.
    """
    return (
        f'mpackage = "{PACKAGE_NAME}"\n'
        f'version = "{version}"\n'
        f'created = "{CREATED}"\n'
        f'author = "PrincessSiren"\n'
        f'title = "Rift restock list for Achaea"\n'
        f"description = [[{DESCRIPTION}]]\n"
        f'helpURL = "{HELP_URL}"\n'
        f'license = "GPL-3.0-or-later"\n'
        f'source = "{SOURCE_URL}"\n'
    )


def license_text() -> str:
    """The licence this package ships under.

    Looked for beside build.py first, then up the tree: a package that has been
    split out into its own repository carries its own copy, one still in the
    workshop shares the root one, and the same build.py works either way.

    It goes *inside* the .mpackage because Mudlet's package format has no
    licence field -- config.lua has no key for it, whatever else it carries --
    so this file is the only way the terms reach anyone who installs the
    package.
    """
    for path in (HERE / "LICENSE", *(p / "LICENSE" for p in HERE.parents)):
        if path.is_file():
            return path.read_text(encoding="utf-8")
    raise SystemExit("no LICENSE beside build.py or anywhere above it")


def build() -> None:
    handwritten = LUA.read_text(encoding="utf-8")
    lua_source = handwritten + commands_lua(handwritten)
    version = read_version(lua_source)
    stamp = build_stamp(handwritten)

    aliases = "".join(
        ALIAS_TEMPLATE.format(
            name=escape(name),
            script=escape(lua),
            package=PACKAGE_NAME,
            regex=escape(regex),
        )
        for name, regex, lua, _usage, _help in ALIASES
    )

    XML.write_text(
        XML_TEMPLATE.format(
            xml_version=XML_VERSION,
            package=PACKAGE_NAME,
            script=escape(lua_source),
            aliases=aliases,
        ),
        encoding="utf-8",
    )

    with zipfile.ZipFile(MPACKAGE, "w") as archive:
        for name, text in (
            (f"{PACKAGE_NAME}.xml", XML.read_text(encoding="utf-8")),
            ("config.lua", config_lua(version)),
            ("LICENSE", license_text()),
        ):
            archive.writestr(zip_entry(name), text)

    print(f"{PACKAGE_NAME} {version} build {stamp} ({len(ALIASES)} aliases)")
    print(f"  `restock diag` in Mudlet should say build {stamp}; "
          f"anything else is a stale install")
    print(f"  wrote {XML.relative_to(HERE.parent)}")
    print(f"  wrote {MPACKAGE.relative_to(HERE.parent)}")


if __name__ == "__main__":
    build()
