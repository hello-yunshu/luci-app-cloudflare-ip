#!/usr/bin/env python3
"""Translation contract: JS/menu keys must exist in POT and every locale.

The check is deliberately dependency-free so CI and maintainers run the same
logic. `msgfmt -c` validates syntax and format placeholders; this script
validates key coverage, empty translations, fuzzy entries and duplicate ids.

Usage:
  python3 tests/i18n-contract.py
  python3 tests/i18n-contract.py --pot /tmp/negative.pot --zh /tmp/negative.po
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PKG = os.path.join(ROOT, 'package/luci-app-cloudflare-ip')
VIEW_DIR = os.path.join(PKG, 'htdocs/luci-static/resources/view/cloudflare-ip')
UTILS = os.path.join(PKG, 'htdocs/luci-static/resources/cloudflare-ip/utils.js')
MENU = os.path.join(PKG, 'root/usr/share/luci/menu.d/luci-app-cloudflare-ip.json')
POT = os.path.join(PKG, 'po/templates/cloudflare-ip.pot')
ZH = os.path.join(PKG, 'po/zh_Hans/cloudflare-ip.po')
EN = os.path.join(PKG, 'po/en/cloudflare-ip.po')

_CALL = re.compile(r"_\(\s*(?:'((?:[^'\\]|\\.)*)'|\"((?:[^\"\\]|\\.)*)\")\s*\)")


def unescape(value):
    out = []
    index = 0
    while index < len(value):
        char = value[index]
        if char == '\\' and index + 1 < len(value):
            escaped = {'n': '\n', 't': '\t', 'r': '\r', '"': '"', "'": "'", '\\': '\\'}
            out.append(escaped.get(value[index + 1], value[index + 1]))
            index += 2
        else:
            out.append(char)
            index += 1
    return ''.join(out)


def js_keys():
    keys = {}
    files = sorted(glob.glob(os.path.join(VIEW_DIR, '*.js'))) + [UTILS]
    for path in files:
        rel = os.path.relpath(path, ROOT)
        with open(path, encoding='utf-8') as handle:
            text = handle.read()
        for match in _CALL.finditer(text):
            key = unescape(match.group(1) if match.group(1) is not None else match.group(2))
            keys.setdefault(key, set()).add(rel)
    return keys


def menu_keys():
    with open(MENU, encoding='utf-8') as handle:
        menu = json.load(handle)
    return [section['title'] for section in menu.values()]


def parse_po(path):
    entries = {}
    cur_id = cur_str = None
    state = None
    fuzzy = False
    fuzzy_ids = []

    def flush():
        nonlocal cur_id, cur_str, state, fuzzy
        if cur_id is not None:
            entries[cur_id] = cur_str or ''
            if fuzzy:
                fuzzy_ids.append(cur_id)
        cur_id = cur_str = None
        state = None
        fuzzy = False

    with open(path, encoding='utf-8') as handle:
        for raw in handle:
            line = raw.rstrip('\n')
            if not line.strip():
                flush()
                continue
            if line.startswith('#,'):
                fuzzy = fuzzy or 'fuzzy' in line
                continue
            if line.startswith('#'):
                continue
            if line.startswith('msgid '):
                if cur_id is not None:
                    flush()
                cur_id = unescape(line[6:].strip())[1:-1]
                state = 'id'
                continue
            if line.startswith('msgstr '):
                cur_str = unescape(line[7:].strip())[1:-1]
                state = 'str'
                continue
            if line.startswith('"'):
                value = unescape(line.strip())[1:-1]
                if state == 'id':
                    cur_id += value
                elif state == 'str':
                    cur_str += value
    flush()
    return entries, fuzzy_ids


def msgfmt(path):
    result = subprocess.run(['msgfmt', '-c', '-o', os.devnull, path],
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit('msgfmt rejected %s:\n%s' % (path, result.stderr.strip()))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pot', default=POT)
    parser.add_argument('--zh', default=ZH)
    parser.add_argument('--en', default=EN)
    args = parser.parse_args()

    keys = js_keys()
    menus = menu_keys()
    for title in menus:
        keys.setdefault(title, set()).add('menu.d/luci-app-cloudflare-ip.json')

    for path in (args.pot, args.zh, args.en):
        msgfmt(path)

    pot, _ = parse_po(args.pot)
    zh, zh_fuzzy = parse_po(args.zh)
    en, en_fuzzy = parse_po(args.en)

    errors = []
    missing_pot = sorted(key for key in keys if key not in pot)
    missing_zh = sorted(key for key in keys if key not in zh or not zh[key].strip())
    missing_en = sorted(key for key in keys if key not in en or not en[key].strip())
    missing_menu = sorted(title for title in menus if title not in pot or title not in zh or not zh[title].strip())
    empty_zh = sorted(key for key in zh if key and zh[key] and not zh[key].strip())
    empty_en = sorted(key for key in en if key and en[key] and not en[key].strip())

    if missing_pot:
        errors.append('missing from POT: ' + ', '.join(missing_pot))
    if missing_zh:
        errors.append('missing/empty zh_Hans: ' + ', '.join(missing_zh))
    if missing_en:
        errors.append('missing/empty en: ' + ', '.join(missing_en))
    if missing_menu:
        errors.append('menu titles missing/empty: ' + ', '.join(missing_menu))
    if zh_fuzzy:
        errors.append('fuzzy zh_Hans entries: ' + ', '.join(zh_fuzzy))
    if en_fuzzy:
        errors.append('fuzzy en entries: ' + ', '.join(en_fuzzy))
    if empty_zh:
        errors.append('empty zh_Hans msgstr: ' + ', '.join(empty_zh))
    if empty_en:
        errors.append('empty en msgstr: ' + ', '.join(empty_en))

    print('i18n keys: %d (JS %d + menu %d)' % (len(keys), len(keys) - len(menus), len(menus)))
    print('coverage: POT %d, zh_Hans %d, en %d' % (len(pot), len(zh), len(en)))
    if errors:
        for error in errors:
            print('FAIL: ' + error, file=sys.stderr)
        return 1
    print('i18n contract: PASS')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
