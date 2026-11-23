#!/usr/bin/env python3
"""Static validator for GuildTabardVote WoW AddOn (Lua 5.1, TOC, Locale, TGA)."""

import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON_DIR = os.path.join(ROOT, "GuildTabardVote")
TOC_PATH = os.path.join(ADDON_DIR, "GuildTabardVote.toc")


def strip_lua(code: str) -> str:
    out = []
    i, n = 0, len(code)
    while i < n:
        if code[i : i + 2] == "--":
            if code[i : i + 4] == "--[[":
                end = code.find("]]", i + 4)
                i = n if end == -1 else end + 2
            else:
                end = code.find("\n", i + 2)
                i = n if end == -1 else end + 1
                out.append("\n")
        elif code[i] in ('"', "'"):
            q = code[i]
            i += 1
            while i < n and code[i] != q:
                i += 2 if code[i] == "\\" else 1
            i += 1
            out.append(" ")
        else:
            out.append(code[i])
            i += 1
    return "".join(out)


def main() -> int:
    if not os.path.isfile(TOC_PATH):
        print(f"ERROR: Missing TOC file: {TOC_PATH}", file=sys.stderr)
        return 1

    with open(TOC_PATH, "r", encoding="utf-8") as f:
        toc_text = f.read()

    if "## Interface: 16001" not in toc_text:
        print("ERROR: TOC must include WoW Forever interface 16001", file=sys.stderr)
        return 1

    lua_files = []
    for line in toc_text.splitlines():
        s = line.strip()
        if s and not s.startswith("#"):
            full = os.path.join(ADDON_DIR, s)
            if not os.path.isfile(full):
                print(f"ERROR: File listed in TOC does not exist: {full}", file=sys.stderr)
                return 1
            if s.endswith(".lua"):
                lua_files.append(full)

    with open(os.path.join(ADDON_DIR, "Locale.lua"), "r", encoding="utf-8") as f:
        loc_src = f.read()

    en_block = loc_src.split("local EN = {")[1].split("local DE = {")[0]
    de_block = loc_src.split("local DE = {")[1].split("GTV.L =")[0]
    en_keys = set(re.findall(r"^\s*([A-Z0-9_]+)\s*=", en_block, re.M))
    de_keys = set(re.findall(r"^\s*([A-Z0-9_]+)\s*=", de_block, re.M))
    if en_keys != de_keys:
        print(f"ERROR: Locale key mismatch: EN-DE={en_keys - de_keys}, DE-EN={de_keys - en_keys}", file=sys.stderr)
        return 1

    pairs = {")": "(", "]": "[", "}": "{"}
    for path in lua_files:
        with open(path, "r", encoding="utf-8") as f:
            src = f.read()
        clean = strip_lua(src)

        stack = []
        for ch in clean:
            if ch in "([{":
                stack.append(ch)
            elif ch in ")]}":
                if not stack or stack[-1] != pairs[ch]:
                    print(f"ERROR: Unbalanced '{ch}' in {path}", file=sys.stderr)
                    return 1
                stack.pop()
        if stack:
            print(f"ERROR: Unclosed {stack} in {path}", file=sys.stderr)
            return 1

        depth = 0
        for tok in re.findall(r"\b(?:function|if|do|repeat|end|until)\b", clean):
            if tok in ("function", "if", "do", "repeat"):
                depth += 1
            else:
                depth -= 1
                if depth < 0:
                    print(f"ERROR: Unexpected '{tok}' in {path}", file=sys.stderr)
                    return 1
        if depth != 0:
            print(f"ERROR: Unbalanced block depth ({depth}) in {path}", file=sys.stderr)
            return 1

        if "//" in clean or re.search(r"\bgoto\b", clean):
            print(f"ERROR: Non-Lua-5.1 syntax found in {path}", file=sys.stderr)
            return 1

        missing_keys = set(re.findall(r"GTV\.L\.([A-Z0-9_]+)", src)) - en_keys
        if missing_keys:
            print(f"ERROR: Undefined locale keys in {path}: {missing_keys}", file=sys.stderr)
            return 1

    for name in ("icon.tga", "thumb_up.tga", "thumb_down.tga"):
        tga_path = os.path.join(ADDON_DIR, "Media", name)
        with open(tga_path, "rb") as f:
            hdr = f.read(18)
            body = f.read()
        _, _, img_type, _, _, _, _, _, w, h, bpp, _ = struct.unpack("<BBBHHBHHHHBB", hdr)
        if not (img_type == 2 and w == 64 and h == 64 and bpp == 32 and len(body) == 64 * 64 * 4):
            print(f"ERROR: Invalid TGA asset: {tga_path}", file=sys.stderr)
            return 1

    print(f"Validation OK: {len(lua_files)} Lua files, {len(en_keys)} EN/DE locale keys, 3 TGA icons.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
