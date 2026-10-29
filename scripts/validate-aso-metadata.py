#!/usr/bin/env python3
"""Validate App Store metadata fields for one or more fastlane locales."""
from __future__ import annotations

import argparse
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
METADATA = ROOT / 'fastlane' / 'metadata'
LIMITS = {
    'name': 30,
    'subtitle': 30,
    'keywords': 100,
    'promotional_text': 170,
    'description': 4000,
}
KEYWORD_RE = re.compile(r'[^\W_]+', re.UNICODE)
CJK_RE = re.compile(r'[\u2e80-\u2eff\u3000-\u30ff\u31f0-\u31ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]')


def normalized(value: str) -> str:
    return unicodedata.normalize('NFKC', value).casefold()


def read_field(locale: str, field: str) -> str:
    path = METADATA / locale / f'{field}.txt'
    if not path.is_file():
        raise ValueError(f'missing {path.relative_to(ROOT)}')
    value = path.read_text(encoding='utf-8')
    if value.endswith('\n'):
        value = value[:-1]
    return value


def validate_locale(locale: str) -> list[str]:
    errors: list[str] = []
    fields: dict[str, str] = {}
    for field, limit in LIMITS.items():
        try:
            value = read_field(locale, field)
        except (OSError, ValueError) as error:
            errors.append(str(error))
            continue
        fields[field] = value
        if value != value.strip():
            errors.append(f'{locale}/{field}: leading or trailing whitespace')
        if len(value) > limit:
            errors.append(f'{locale}/{field}: {len(value)} characters, limit {limit}')
        if '\u2014' in value:
            errors.append(f'{locale}/{field}: em dash')

    keywords = fields.get('keywords')
    if keywords is None:
        return errors
    tokens = keywords.split(',')
    normalized_tokens = [normalized(token) for token in tokens]
    if any(not token for token in tokens):
        errors.append(f'{locale}/keywords: empty comma-separated token')
    if any(token != token.strip() or any(char.isspace() for char in token) for token in tokens):
        errors.append(f'{locale}/keywords: spaces around or inside a token')
    if len(set(normalized_tokens)) != len(normalized_tokens):
        errors.append(f'{locale}/keywords: duplicate keyword tokens')

    title_subtitle = normalized(fields.get('name', '') + ' ' + fields.get('subtitle', ''))
    title_tokens = {normalized(token) for token in KEYWORD_RE.findall(fields.get('name', '') + ' ' + fields.get('subtitle', ''))}
    for token in normalized_tokens:
        if not token:
            continue
        duplicate = token in title_tokens
        if CJK_RE.search(token) and token in title_subtitle:
            duplicate = True
        if duplicate:
            errors.append(f'{locale}/keywords: {token!r} repeats name or subtitle')
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('locales', nargs='+', help='fastlane locale folders to validate')
    args = parser.parse_args()

    errors = [error for locale in args.locales for error in validate_locale(locale)]
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1

    for locale in args.locales:
        counts = {field: len(read_field(locale, field)) for field in LIMITS}
        print(f'{locale}: ' + ', '.join(f'{field}={count}/{LIMITS[field]}' for field, count in counts.items()))
    print(f'Valid: {len(args.locales)} locale(s)')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
