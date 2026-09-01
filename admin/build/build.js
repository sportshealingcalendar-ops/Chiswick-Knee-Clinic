#!/usr/bin/env node
'use strict';
// Regenerate everything derived from VERSION and the page tree, so nothing is
// hand-edited twice: the version stamp on every page, sitemap.xml, robots.txt.
//
//   node admin/build/build.js          write the generated files
//   node admin/build/build.js --check  exit 1 if anything is out of date
//
// The validator runs --check, which is what makes "did you re-run the build?"
// a machine question rather than a review comment.

const fs = require('fs');
const path = require('path');
const { ROOT, readConfig, readVersion, listPages, buildSitemap, buildRobots, stamp } = require('./lib');

const check = process.argv.includes('--check');
const cfg = readConfig();
const version = readVersion();
const pages = listPages();

const stale = [];

function emit(rel, next) {
  const abs = path.join(ROOT, rel);
  const prev = fs.existsSync(abs) ? fs.readFileSync(abs, 'utf8') : null;
  if (prev === next) return;
  if (check) {
    stale.push(rel);
    return;
  }
  fs.writeFileSync(abs, next);
  console.log(`  wrote ${rel}`);
}

console.log(`${check ? 'checking' : 'building'} ${cfg.name} ${version} (${pages.length} pages)`);

for (const rel of pages) {
  emit(rel, stamp(fs.readFileSync(path.join(ROOT, rel), 'utf8'), version));
}
emit('sitemap.xml', buildSitemap(pages, cfg));
emit('robots.txt', buildRobots(cfg));

if (check && stale.length) {
  console.error(`\nFAIL out of date, re-run "node admin/build/build.js":`);
  for (const f of stale) console.error(`  - ${f}`);
  process.exit(1);
}

console.log(check ? 'up to date' : 'done');
