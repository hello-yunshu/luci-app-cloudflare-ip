'use strict';

/*
 * Phase F evidence verifier.
 * Reads the matrix and zoom/zh evidence, checks the evidence index,
 * screenshot hashes, console-error emptiness and N/A explanations.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '../..'); // next-release-evidence
const MATRIX = path.join(ROOT, 'phase-f/matrix/matrix.json');
const ZOOM = path.join(ROOT, 'phase-f/zoom-zh/zoom-zh.json');
const EXPECTED_SHA = process.env.CFIP_UI_SHA || 'ffa73f6';
const STATES = ['loading', 'disabled', 'error', 'success', 'partial', 'cancel', 'rollback'];

function sha(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

const failures = [];
const warnings = [];

if (!fs.existsSync(MATRIX)) failures.push('matrix.json missing');
if (!fs.existsSync(ZOOM)) failures.push('zoom-zh.json missing');

let matrix = null;
let zoom = null;
if (fs.existsSync(MATRIX)) matrix = JSON.parse(fs.readFileSync(MATRIX, 'utf8'));
if (fs.existsSync(ZOOM)) zoom = JSON.parse(fs.readFileSync(ZOOM, 'utf8'));

const counts = {};
if (matrix) {
  if (matrix.sha !== EXPECTED_SHA) failures.push(`matrix sha ${matrix.sha} != ${EXPECTED_SHA}`);
  if (matrix.points.length !== 51) failures.push(`matrix has ${matrix.points.length} points`);
  const missing = [];
  for (const row of matrix.points) {
    if (row.status !== 'PASS') failures.push(`${row.id}: status ${row.status}`);
    if (!row.environment || row.environment.sha !== EXPECTED_SHA) failures.push(`${row.id}: missing environment sha`);
    if (!row.environment.theme) warnings.push(`${row.id}: theme not captured`);
    for (const state of STATES) {
      if (row.states[state] === 'N/A') {
        if (!row.note || !row.note[state] || !String(row.note[state]).trim())
          failures.push(`${row.id}/${state}: N/A without reason`);
        continue;
      }
      if (row.states[state] !== 'PASS') {
        failures.push(`${row.id}/${state}: ${row.states[state]}`);
        continue;
      }
      counts[state] = counts[state] || { PASS: 0, 'N/A': 0 };
      counts[state].PASS += 1;
      const idx = (row.evidenceIndex || {})[state] || [];
      if (!idx.length) failures.push(`${row.id}/${state}: empty evidence index`);
      for (const item of idx) {
        const file = path.join(ROOT, item.file);
        if (!fs.existsSync(file)) {
          failures.push(`${row.id}/${state}: missing ${item.file}`);
          continue;
        }
        if (sha(file) !== item.sha256) failures.push(`${row.id}/${state}: sha mismatch ${item.file}`);
      }
      if (!row.consoleErrors || !Array.isArray(row.consoleErrors[state]) || row.consoleErrors[state].length)
        failures.push(`${row.id}/${state}: console errors not empty`);
      const before = idx.find(i => i.file.endsWith('-before.png'));
      const after = idx.find(i => i.file.endsWith('-after.png'));
      if (before && after && before.sha256 === after.sha256) {
        const allowance = (row.note && row.note.errorScreenshot) ||
          (row.assertions && row.assertions[state] &&
            (row.assertions[state].transient || row.assertions[state].evidenceReusedFrom));
        const explained = (row.note && row.note.errorScreenshot) ||
          (row.assertions && row.assertions[state] && row.assertions[state].screenshotNote);
        if (!allowance || !explained)
          failures.push(`${row.id}/${state}: before/after hashes identical without a transient note`);
      }
      if (!row.assertions || !row.assertions[state] || !row.assertions[state].dom || !row.assertions[state].focus)
        failures.push(`${row.id}/${state}: DOM/focus assertion missing`);
      if (!row.assertions[state].persistence) failures.push(`${row.id}/${state}: persistence assertion missing`);
    }
    for (const state of STATES) if (row.states[state] === 'N/A') counts[state] = counts[state] || { PASS: 0, 'N/A': 0 }, counts[state]['N/A'] += 1;
  }
  if (matrix.missingEvidence && matrix.missingEvidence.length) failures.push(`missingEvidence: ${matrix.missingEvidence.join(',')}`);
  if (missing.length) warnings.push(...missing);
}

const zoomHashes = {};
let zoomCount = 0;
if (zoom) {
  if (zoom.sha !== EXPECTED_SHA) failures.push(`zoom sha ${zoom.sha} != ${EXPECTED_SHA}`);
  if (!zoom.assertions || !zoom.assertions.passed) failures.push(`zoom assertions failed: ${zoom.assertions && zoom.assertions.failed}`);
  for (const section of ['zoom', 'reflow320', 'zh']) {
    for (const row of zoom[section] || []) {
      const file = path.join(ROOT, row.screenshot || '');
      if (!row.screenshot || !fs.existsSync(file)) {
        failures.push(`${section} ${row.page}: screenshot missing`);
        continue;
      }
      zoomCount += 1;
      const hash = sha(file);
      zoomHashes[hash] = (zoomHashes[hash] || 0) + 1;
      if (row.consoleErrors && row.consoleErrors.length) failures.push(`${section} ${row.page}: console errors`);
    }
  }
  if (zoom.zoom.length !== 24) failures.push(`zoom rows ${zoom.zoom.length} != 24`);
  if (zoom.reflow320.length !== 8) failures.push(`reflow rows ${zoom.reflow320.length} != 8`);
  if (zoom.zh.length !== 16) failures.push(`zh rows ${zoom.zh.length} != 16`);
  const duplicates = Object.entries(zoomHashes).filter(([, n]) => n > 1);
  if (duplicates.length) warnings.push(`duplicate screenshots: ${duplicates.length} hashes`);
}

const summary = {
  schemaVersion: 1,
  sha: EXPECTED_SHA,
  matrix: { points: matrix ? matrix.points.length : 0, counts, failures: failures.filter(f => !f.startsWith('zoom')).length },
  zoom: { screenshots: zoomCount, uniqueHashes: Object.keys(zoomHashes).length },
  passed: failures.length === 0,
  failed: failures.length,
  failures,
  warnings
};
fs.writeFileSync(path.join(ROOT, 'phase-f/verify.json'), JSON.stringify(summary, null, 2) + '\n');
console.log(JSON.stringify(summary, null, 2));
process.exit(failures.length ? 1 : 0);
