#!/usr/bin/env python3
"""Generate a single-file Neovim config from init.lua module requires."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


REQUIRE = re.compile(
    r"""require\s*
        (?:
            \(\s*["'](?P<mod1>[^"']+)["']\s*\)
            |
            ["'](?P<mod2>[^"']+)["']
        )
    """,
    re.VERBOSE,
)
TOP_LEVEL_REQUIRE = re.compile(
    r"""^
        (?:
            local\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*
            |
            [A-Za-z_][A-Za-z0-9_]*\s*=\s*
        )?
        require\s*
        (?:
            \(\s*["'](?P<mod1>[^"']+)["']\s*\)
            |
            ["'](?P<mod2>[^"']+)["']
        )
    """,
    re.VERBOSE | re.MULTILINE,
)


def lua_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def module_path(root: Path, module: str) -> Path:
    return root / "lua" / Path(*module.split(".")).with_suffix(".lua")


def variable_prefix(module: str) -> str:
    return "_inlined_" + re.sub(r"[^A-Za-z0-9_]", "_", module)


def strip_lua_comments(text: str) -> str:
    result: list[str] = []
    index = 0

    while index < len(text):
        if text.startswith("--[[", index):
            end = text.find("]]", index + 4)
            stop = len(text) if end == -1 else end + 2
            result.append(re.sub(r"[^\n]", " ", text[index:stop]))
            index = stop
            continue

        if text.startswith("--", index):
            end = text.find("\n", index + 2)
            stop = len(text) if end == -1 else end
            result.append(" " * (stop - index))
            index = stop
            continue

        result.append(text[index])
        index += 1

    return "".join(result)


def find_requires(text: str) -> list[str]:
    found: list[str] = []

    for match in REQUIRE.finditer(strip_lua_comments(text)):
        module = match.group("mod1") or match.group("mod2")
        if module and module not in found:
            found.append(module)

    return found


def find_top_level_requires(text: str) -> list[str]:
    found: list[str] = []

    for match in TOP_LEVEL_REQUIRE.finditer(strip_lua_comments(text)):
        module = match.group("mod1") or match.group("mod2")
        if module and module not in found:
            found.append(module)

    return found


def rename_module_tables(text: str, module: str) -> tuple[str, str | None]:
    prefix = variable_prefix(module)
    public_name = f"{prefix}_M"
    private_name = f"{prefix}_P"

    if re.search(r"(?m)^\s*local\s+M\s*=", text):
        text = re.sub(r"\bM\b", public_name, text)

    if re.search(r"(?m)^\s*local\s+_P\s*=", text):
        text = re.sub(r"\b_P\b", private_name, text)

    return text, public_name


def replace_final_return(text: str, module: str, public_name: str | None) -> tuple[str, bool]:
    pattern = re.compile(r"(?m)^return\s+(?P<expr>[^\n]+)\s*$")
    matches = list(pattern.finditer(text))

    if not matches:
        return text, False

    match = matches[-1]
    expression = match.group("expr").strip()
    replacement = f"package.loaded[{lua_string(module)}] = {expression}"

    return text[: match.start()] + replacement + text[match.end() :], True


def indent_block(text: str, spaces: int = 4) -> str:
    prefix = " " * spaces
    return "\n".join(prefix + line if line else "" for line in text.splitlines())


class Inliner:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.done: set[str] = set()
        self.visiting: set[str] = set()
        self.blocks: list[str] = []
        self.extra_modules: set[str] = set()

    def inline_module(self, module: str) -> None:
        path = module_path(self.root, module)
        if not path.exists():
            return

        if module in self.done:
            return

        if module in self.visiting:
            raise RuntimeError(f"circular local require detected for {module}")

        self.visiting.add(module)
        source = path.read_text()

        for dependency in find_requires(source):
            if dependency.startswith("modules."):
                self.extra_modules.add(dependency)

        for dependency in find_top_level_requires(source):
            if dependency.startswith("modules."):
                self.inline_module(dependency)

        renamed, public_name = rename_module_tables(source.rstrip(), module)
        rewritten, had_return = replace_final_return(renamed, module, public_name)

        if not had_return:
            rewritten = rewritten.rstrip() + f"\n\npackage.loaded[{lua_string(module)}] = true"

        relative = path.relative_to(self.root).as_posix()
        block = "\n".join(
            [
                f"do -- {module} ({relative})",
                indent_block(rewritten),
                "end",
            ]
        )

        self.blocks.append(block)
        self.visiting.remove(module)
        self.done.add(module)


def generate(root: Path, input_path: Path) -> str:
    source = input_path.read_text()
    inliner = Inliner(root)
    output: list[str] = [
        "-- Generated from init.lua by inline_init.py.",
        "-- Do not edit this file directly; edit modules and regenerate.",
        "-- luacheck: ignore 631",
        "---@diagnostic disable: duplicate-doc-field,duplicate-doc-alias,duplicate-set-field",
        "",
    ]

    for line in source.splitlines():
        match = REQUIRE.search(strip_lua_comments(line))
        module = match and (match.group("mod1") or match.group("mod2"))

        if module and module.startswith("modules.") and module_path(root, module).exists():
            inliner.inline_module(module)
            output.extend(inliner.blocks)
            inliner.blocks.clear()
            output.append("")
        else:
            output.append(line)

    while True:
        pending = sorted(module for module in inliner.extra_modules if module not in inliner.done)
        if not pending:
            break

        output.append("")
        output.append("-- Extra local modules required lazily by startup modules.")

        for module in pending:
            inliner.inline_module(module)
            output.extend(inliner.blocks)
            inliner.blocks.clear()
            output.append("")

    return "\n".join(output).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--input", type=Path, default=Path("init.lua"))
    parser.add_argument("--output", type=Path, default=Path(".generated/noplugins-init.lua"))
    args = parser.parse_args()

    root = args.root.resolve()
    input_path = args.input if args.input.is_absolute() else root / args.input
    output_path = args.output if args.output.is_absolute() else root / args.output

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(generate(root, input_path))
    print(f"Wrote {output_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
