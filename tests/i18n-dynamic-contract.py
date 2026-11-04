#!/usr/bin/env python3
"""Dynamic status and raw-error contract.

Fails when a known backend code has no user-facing mapping, or when a view
passes a raw error into a toast without the shared technical-details wrapper.
"""
import argparse
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UTILS = os.path.join(ROOT, 'package/luci-app-cloudflare-ip/htdocs/luci-static/resources/cloudflare-ip/utils.js')
VIEWS = os.path.join(ROOT, 'package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip')
POT = os.path.join(ROOT, 'package/luci-app-cloudflare-ip/po/templates/cloudflare-ip.pot')

REQUIRED = {
    'mode': ['off', 'shadow', 'assisted', 'guarded', 'native'],
    'qualification': ['cold', 'insufficient', 'qualified', 'pending', 'unknown'],
    'health': ['healthy', 'degraded', 'unhealthy', 'unknown', 'unavailable', 'error'],
    'confidence': ['high', 'medium', 'low', 'unknown', 'unavailable'],
    'runtime': ['disabled', 'not-installed', 'ready', 'error', 'unavailable'],
    'error': ['none', 'timeout', 'unavailable', 'not_installed', 'invalid_response', 'permission_denied', 'error'],
    'reason': ['disabled', 'manual_reset', 'insufficient_feedback', 'insufficient_samples',
               'qualification_missing', 'not_qualified', 'runtime_unavailable', 'runtime_not_installed',
               'consumer_unavailable', 'consumer_not_qualified', 'context_changed', 'stale_evidence',
               'holdout_censored', 'resource_pressure', 'timeout', 'error'],
}
REQUIRED_SOURCE = ['fetch_failed', 'parse_failed', 'timeout', 'http_error', 'invalid_url',
                   'unsupported_content', 'empty', 'disabled']


def mapping_keys(text, name):
    match = re.search(r'var\s+%s\s*=\s*\{' % name, text)
    if not match:
        return set()
    start = match.end()
    depth = 1
    index = start
    while index < len(text) and depth:
        depth += text[index] == '{'
        depth -= text[index] == '}'
        index += 1
    body = text[start:index - 1]
    return set(re.findall(r'(?m)^\s*([\w\'"-]+)\s*:\s*_\(', body))


def status_table_keys(text, kind):
    match = re.search(r'(?m)^\s*%s\s*:\s*\{' % re.escape(kind), text)
    if not match:
        return set()
    start = match.end()
    depth = 1
    index = start
    while index < len(text) and depth:
        depth += text[index] == '{'
        depth -= text[index] == '}'
        index += 1
    body = text[start:index - 1]
    return set(key.strip("'\"") for key in re.findall(r'(?m)^\s*([\w\'"-]+)\s*:\s*_\(', body))


def raw_toast_errors(text):
    errors = []
    for path in sorted(glob.glob(os.path.join(VIEWS, '*.js'))):
        source = open(path, encoding='utf-8').read()
        for match in re.finditer(r'ui\.addNotification\(', source):
            chunk = source[match.start():match.start() + 700]
            if 'utils.errorNotice' in chunk or 'utils.noticeError' in chunk or 'utils.errorPanel' in chunk:
                continue
            raw_format = re.search(r'\.format\([^)]*(?:\.message|\.error|e\b|\|)', chunk)
            translated = re.search(r'_\s*\(', chunk)
            if raw_format or (not translated and re.search(r'ui\.addNotification\([^;]*?[\'"][A-Z][^\'"]*[\'"]', chunk)):
                line = source[:match.start()].count('\n') + 1
                errors.append('%s:%d raw notification without technical details' % (os.path.basename(path), line))
    return errors


def check(text):
    errors = []
    for kind, required in REQUIRED.items():
        found = status_table_keys(text, kind)
        missing = [code for code in required if code not in found]
        if missing:
            errors.append('STATUS_LABELS.%s missing: %s' % (kind, ', '.join(missing)))
    source = mapping_keys(text, 'SOURCE_ERROR_LABELS')
    missing = [code for code in REQUIRED_SOURCE if code not in source]
    if missing:
        errors.append('SOURCE_ERROR_LABELS missing: %s' % ', '.join(missing))
    errors.extend(raw_toast_errors(text))
    return errors


def self_test(text):
    broken = text.replace("\t\ttimeout: _('Timeout'),\n", '', 1)
    if broken == text:
        print('FAIL self-test could not remove a mapping entry', file=sys.stderr)
        return 1
    errors = check(broken)
    if not any('STATUS_LABELS.error missing: timeout' in error for error in errors):
        print('FAIL self-test did not detect a missing mapping', file=sys.stderr)
        return 1
    print('PASS negative self-test: removed mapping is detected')
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    text = open(UTILS, encoding='utf-8').read()
    if args.self_test:
        return self_test(text)
    errors = check(text)
    if errors:
        for error in errors:
            print('FAIL: ' + error, file=sys.stderr)
        return 1
    print('PASS dynamic status mappings and raw-error notices')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
