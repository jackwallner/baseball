#!/usr/bin/env python3
"""Check StatScout's Swift UI strings against its string catalog.

Run from the repository root with: python3 Tools/Localization/check.py
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "StatScout"
CATALOG = SOURCE_DIR / "Resources" / "Localizable.xcstrings"
LANGUAGES = ["es", "fr", "it", "ja", "pt-BR", "zh-Hant", "ko", "zh-Hans", "de"]
UI_FUNCS = {
    "Text", "Button", "Label", "Section", "Toggle", "TextField", "navigationTitle",
    "accessibilityLabel", "accessibilityHint", "alert", "DatePicker", "Stepper", "Link",
    "confirmationDialog", "Picker", "SecureField", "Menu", "configurationDisplayName",
    "description", "keyboardShortcut", "confirmationDialog", "navigationSubtitle",
}
IGNORED = {"0"}


def has_words(key: str) -> bool:
    remaining = re.sub(r"%(?:\d+\$)?(?:lld|@)|%%", "", key)
    if remaining.strip() in {"A", "B", "Δ"}:
        return False
    letters = {char for char in remaining if char.isalpha()}
    return bool(letters - {"G", "Δ"})


def parse_literal(src: str, i: int):
    """Return the end and literal/interpolation segments for a Swift string."""
    if src.startswith('"""', i):
        end = src.index('"""', i + 3)
        return end + 3, None

    i += 1
    segments = []
    buffer = ""
    while True:
        char = src[i]
        if char == '"':
            if buffer:
                segments.append(("lit", buffer))
            return i + 1, segments
        if char == "\\":
            next_char = src[i + 1]
            if next_char == "(":
                if buffer:
                    segments.append(("lit", buffer))
                    buffer = ""
                depth = 1
                j = i + 2
                expression = ""
                while depth:
                    current = src[j]
                    if current == '"':
                        end, _ = parse_literal(src, j)
                        expression += src[j:end]
                        j = end
                        continue
                    if current == "(":
                        depth += 1
                    elif current == ")":
                        depth -= 1
                        if depth == 0:
                            break
                    expression += current
                    j += 1
                segments.append(("interp", expression.strip()))
                i = j + 1
                continue
            if next_char == "u":
                end = src.index("}", i)
                buffer += chr(int(src[i + 3:end], 16))
                i = end + 1
                continue
            buffer += {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'", "0": "\0"}.get(next_char, next_char)
            i += 2
            continue
        buffer += char
        i += 1


def scan(path: Path):
    src = path.read_text()
    found = []
    stack = []
    i = 0
    line = 1
    while i < len(src):
        char = src[i]
        if char == "\n":
            line += 1
        if src.startswith("//", i):
            end = src.find("\n", i)
            i = len(src) if end < 0 else end
            continue
        if src.startswith("/*", i):
            end = src.index("*/", i)
            line += src[i:end].count("\n")
            i = end + 2
            continue
        if char == '"':
            end, segments = parse_literal(src, i)
            if segments is not None and stack:
                func, arguments, index = stack[-1]
                context = None
                if func == "String" and arguments.strip().startswith("localized:"):
                    context = "String(localized:)"
                elif func in UI_FUNCS and index == 0 and not re.match(r"\s*[A-Za-z_]+\s*:", arguments):
                    context = func
                if context:
                    found.append((line, context, segments))
            line += src[i:end].count("\n")
            if stack:
                func, arguments, index = stack[-1]
                stack[-1] = (func, arguments + src[i:end], index)
            i = end
            continue
        if char == "(":
            match = re.search(r"([A-Za-z_][A-Za-z_0-9]*)\s*$", src[max(0, i - 60):i])
            stack.append((match.group(1) if match else "", "", 0))
            i += 1
            continue
        if char == ")":
            if stack:
                stack.pop()
            i += 1
            continue
        if char == "," and stack:
            func, _, index = stack[-1]
            stack[-1] = (func, "", index + 1)
            i += 1
            continue
        if stack:
            func, arguments, index = stack[-1]
            stack[-1] = (func, arguments + char, index)
        i += 1
    return found


def loose(key: str) -> str:
    return re.sub(r"%(\d+\$)?(lld|@)", "%*", key)


def specs(value: str):
    result = []
    next_position = 0
    for match in re.finditer(r"%(?:(\d+)\$)?(lld|@|%)", value):
        if match.group(2) == "%":
            continue
        next_position += 1
        result.append((int(match.group(1) or next_position), match.group(2)))
    return sorted(result)


def main() -> int:
    catalog = json.loads(CATALOG.read_text())["strings"]
    by_loose = {loose(key): key for key in catalog}
    problems = []

    for path in SOURCE_DIR.rglob("*.swift"):
        for line, _, segments in scan(path):
            has_interpolation = any(kind == "interp" for kind, _ in segments)
            key = "".join(
                (value.replace("%", "%%") if has_interpolation else value) if kind == "lit" else "%@"
                for kind, value in segments
            )
            if key.strip() and key not in IGNORED and has_words(key) and loose(key) not in by_loose:
                problems.append(f"{path.relative_to(ROOT)}:{line}: no catalog key for {key!r}")

    for key, entry in catalog.items():
        localizations = entry.get("localizations", {})
        for language in LANGUAGES:
            localization = localizations.get(language)
            if localization is None:
                problems.append(f"{key!r}: missing {language}")
                continue
            if localization.get("stringUnit", {}).get("state") != "translated":
                problems.append(f"{key!r}: {language} is not marked translated")
            value = localization.get("stringUnit", {}).get("value", "")
            if specs(value) != specs(key):
                problems.append(f"{key!r} [{language}]: format specifiers differ in {value!r}")

    for problem in problems:
        print(problem)
    print(f"{len(catalog)} keys, {len(LANGUAGES)} languages, {len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
