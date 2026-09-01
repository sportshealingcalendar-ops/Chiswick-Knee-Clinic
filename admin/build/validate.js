#!/usr/bin/env node
'use strict';
// The test suite. Zero dependencies, so CI cannot be broken by a registry
// outage, and any failure aborts the release before either the tag or the
// deploy is attempted.
//
//   node admin/build/validate.js
//
// Every check here exists to catch a class of silent failure - a page that
// deploys fine and is still, in the only sense that matters, unpublished:
// nothing links to it, no sitemap lists it, or its version stamp is a lie.

const fs = require('fs');
const path = require('path');
const vm = require('vm');
const cp = require('child_process');
const { ROOT, readConfig, readVersion, listPages, urlFor, buildSitemap, buildRobots } = require('./lib');

const cfg = readConfig();
const version = readVersion();
const pages = listPages();

let checks = 0;
const failures = [];

function ok(label) {
  checks++;
  console.log(`  ok   ${label}`);
}

function fail(label, detail) {
  checks++;
  failures.push(detail ? `${label}\n         ${detail}` : label);
  console.log(`  FAIL ${label}${detail ? `\n         ${detail}` : ''}`);
}

function assert(cond, label, detail) {
  cond ? ok(label) : fail(label, detail);
}

function read(rel) {
  return fs.readFileSync(path.join(ROOT, rel), 'utf8');
}

function section(title) {
  console.log(`\n== ${title}`);
}

// ---------------------------------------------------------------- structure

section('structure');

for (const rel of ['index.html', '404.html', 'VERSION', '.nojekyll', 'assets/site.css']) {
  assert(fs.existsSync(path.join(ROOT, rel)), `present: ${rel}`, 'required file is missing');
}
assert(pages.length > 0, 'at least one page exists');
assert(
  !fs.existsSync(path.join(ROOT, 'Index.html')) || fs.existsSync(path.join(ROOT, 'index.html')),
  'entry point is lowercase index.html',
  'GitHub Pages serves index.html; Index.html is a 404 on a case-sensitive host'
);

// ------------------------------------------------------------ generated files

section('generated files are current');

const genExpect = { 'sitemap.xml': buildSitemap(pages, cfg), 'robots.txt': buildRobots(cfg) };
for (const [rel, want] of Object.entries(genExpect)) {
  const have = fs.existsSync(path.join(ROOT, rel)) ? read(rel) : null;
  assert(have === want, `regenerated: ${rel}`, 'stale or missing - run: node admin/build/build.js');
}

try {
  cp.execFileSync(process.execPath, [path.join(__dirname, 'build.js'), '--check'], { stdio: 'pipe' });
  ok('version stamps match VERSION on every page');
} catch (e) {
  fail(
    'version stamps match VERSION on every page',
    String(e.stdout || '').trim() + String(e.stderr || '').trim()
  );
}

// ------------------------------------------------------------------- per page

section(`per-page contract (${pages.length} pages)`);

const linkTargets = new Map(); // page -> local .html pages it links to

for (const rel of pages) {
  const html = read(rel);
  const label = (what) => `${rel}: ${what}`;

  assert(/<html[^>]+lang="[a-zA-Z-]+"/.test(html), label('has lang'), 'add lang to <html>');

  const title = /<title>([^<]*)<\/title>/.exec(html);
  assert(title && title[1].trim().length > 10, label('has a real <title>'));

  const desc = /<meta\s+name="description"\s+content="([^"]*)"/.exec(html);
  assert(desc && desc[1].trim().length > 30, label('has a meta description'));

  const wantUrl = urlFor(rel, cfg.baseUrl);
  const canon = /<link\s+rel="canonical"\s+href="([^"]*)"/.exec(html);
  assert(
    canon && canon[1] === wantUrl,
    label('canonical URL is correct'),
    canon ? `found ${canon[1]}, expected ${wantUrl}` : 'no canonical link'
  );

  const stampMeta = /<meta\s+name="site-version"\s+content="([^"]*)"/.exec(html);
  assert(
    stampMeta && stampMeta[1] === version,
    label('carries the version stamp'),
    'every page needs <meta name="site-version"> so the live deploy can be verified'
  );

  // Structured data: present, and parses. A page without it is invisible to
  // the search and assistant surfaces that read this kind of site.
  const ld = [...html.matchAll(/<script\s+type="application\/ld\+json">([\s\S]*?)<\/script>/g)];
  if (ld.length === 0) {
    fail(label('has JSON-LD structured data'), 'add a schema.org block');
  } else {
    let bad = null;
    for (const m of ld) {
      try {
        JSON.parse(m[1]);
      } catch (e) {
        bad = e.message;
      }
    }
    assert(!bad, label('JSON-LD parses'), bad);
  }

  // Inline classic scripts must parse.
  for (const m of html.matchAll(/<script(?![^>]*\bsrc=)(?![^>]*ld\+json)[^>]*>([\s\S]*?)<\/script>/g)) {
    if (!m[1].trim()) continue;
    try {
      new vm.Script(m[1]);
      ok(label('inline script parses'));
    } catch (e) {
      fail(label('inline script parses'), e.message);
    }
  }

  // Every href/src resolves against the real file tree.
  const targets = new Set();
  let linkFailures = 0;
  for (const m of html.matchAll(/(?:href|src)="([^"]*)"/g)) {
    const raw = m[1];
    const clean = raw.split('#')[0].split('?')[0];
    if (!clean) continue;
    if (/^(?:[a-z][a-z0-9+.-]*:|\/\/)/i.test(clean)) continue; // external / mailto / tel / data

    if (clean.startsWith('/')) {
      fail(
        label(`link "${raw}" is root-absolute`),
        'this site is served from a sub-path; use a relative link'
      );
      linkFailures++;
      continue;
    }

    let target = path.posix.normalize(path.posix.join(path.posix.dirname(rel), clean));
    if (target === '.') target = 'index.html';
    if (clean.endsWith('/') || fs.existsSync(path.join(ROOT, target)) && fs.statSync(path.join(ROOT, target)).isDirectory()) {
      target = path.posix.join(target, 'index.html');
    }

    if (fs.existsSync(path.join(ROOT, target))) {
      if (target.endsWith('.html')) targets.add(target);
    } else {
      fail(label(`link "${raw}" resolves`), `no file at ${target}`);
      linkFailures++;
    }
  }
  if (linkFailures === 0) ok(label('every internal link resolves'));
  linkTargets.set(rel, targets);

  // External local scripts and stylesheets referenced by this page.
  for (const m of html.matchAll(/<script[^>]+src="([^"]+\.js)"/g)) {
    const clean = m[1].split('?')[0];
    if (/^(?:[a-z][a-z0-9+.-]*:|\/\/)/i.test(clean)) continue;
    const target = path.posix.normalize(path.posix.join(path.posix.dirname(rel), clean));
    const abs = path.join(ROOT, target);
    if (!fs.existsSync(abs)) continue; // already reported by the link check
    try {
      new vm.Script(fs.readFileSync(abs, 'utf8'));
      ok(`${target}: parses`);
    } catch (e) {
      fail(`${target}: parses`, e.message);
    }
  }
}

// --------------------------------------------------------------- reachability

section('reachability');

// A page nothing links to is unpublished, however green the deploy was.
const exemptOrphan = new Set(cfg.orphanExempt || []);
const seen = new Set(['index.html']);
const queue = ['index.html'];
while (queue.length) {
  for (const next of linkTargets.get(queue.shift()) || []) {
    if (!seen.has(next)) {
      seen.add(next);
      queue.push(next);
    }
  }
}
const orphans = pages.filter((p) => !seen.has(p) && !exemptOrphan.has(p));
assert(
  orphans.length === 0,
  'no orphan pages',
  `unreachable from index.html: ${orphans.join(', ')}`
);

const missingFromSitemap = pages
  .filter((p) => !(cfg.sitemapExempt || []).includes(p))
  .filter((p) => !read('sitemap.xml').includes(`<loc>${urlFor(p, cfg.baseUrl)}</loc>`));
assert(
  missingFromSitemap.length === 0,
  'sitemap lists every page',
  missingFromSitemap.join(', ')
);
assert(
  read('robots.txt').includes(`${cfg.baseUrl}sitemap.xml`),
  'robots.txt points at the sitemap'
);

// -------------------------------------------------------------- content policy

section('content policy');

const banned = (cfg.bannedWords || []).map((w) => ({
  word: w,
  re: new RegExp(`\\b${w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'i'),
}));
let bannedHits = 0;
for (const rel of pages) {
  const html = read(rel);
  for (const { word, re } of banned) {
    if (re.test(html)) {
      fail(`${rel}: banned phrase "${word}"`, 'outcome guarantees and superlatives must not reach a page');
      bannedHits++;
    }
  }
}
if (bannedHits === 0) ok(`no banned phrases (${banned.length} patterns)`);

// ------------------------------------------------------------ secret tripwire

section('secret tripwire');

// Scanning tracked files only: an untracked scratch file cannot leak.
// Honest edge: this file is excluded from the literal scan, because it holds
// the patterns themselves. A secret pasted into the validator is not caught.
const SELF = 'admin/build/validate.js';
const BINARY = /\.(png|jpe?g|gif|webp|avif|ico|pdf|woff2?|ttf|otf|mp4|webm|zip|gz)$/i;

let tracked = [];
try {
  tracked = cp
    .execFileSync('git', ['ls-files'], { cwd: ROOT, encoding: 'utf8' })
    .split('\n')
    .filter((f) => f && !BINARY.test(f));
} catch {
  fail('git ls-files', 'not a git repository - cannot scan tracked files');
}

const PATTERNS = [
  [/-----BEGIN[ A-Z]*PRIVATE KEY-----/, 'private key block'],
  [/AKIA[0-9A-Z]{16}/, 'AWS access key id'],
  [/gh[pousr]_[A-Za-z0-9]{30,}/, 'GitHub token'],
  [/xox[baprs]-[A-Za-z0-9-]{10,}/, 'Slack token'],
  [/AIza[0-9A-Za-z_-]{35}/, 'Google API key'],
  [/sk-[A-Za-z0-9]{32,}/, 'provider secret key'],
  [/(?:api[_-]?key|secret|password|passphrase|auth[_-]?token)["']?\s*[:=]\s*["'][^"'\s]{16,}["']/i, 'inline credential assignment'],
];

const literals = [];
const literalFile = path.join(__dirname, '.secret-strings');
if (fs.existsSync(literalFile)) {
  literals.push(
    ...fs.readFileSync(literalFile, 'utf8').split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#'))
  );
}

let secretHits = 0;
for (const rel of tracked) {
  if (rel === SELF) continue;
  let text;
  try {
    text = fs.readFileSync(path.join(ROOT, rel), 'utf8');
  } catch {
    continue;
  }
  for (const [re, what] of PATTERNS) {
    if (re.test(text)) {
      fail(`${rel}: looks like a committed ${what}`, 'remove it, rotate the credential, then re-run');
      secretHits++;
    }
  }
  for (const lit of literals) {
    if (text.includes(lit)) {
      fail(`${rel}: contains a known-secret literal`, 'listed in admin/build/.secret-strings');
      secretHits++;
    }
  }
}
if (secretHits === 0) {
  ok(
    `no secrets in ${tracked.length} tracked files` +
      (literals.length ? ` (+${literals.length} literal tripwire${literals.length > 1 ? 's' : ''})` : '')
  );
}

// ------------------------------------------------------------------- verdict

console.log(`\n${'-'.repeat(60)}`);
if (failures.length) {
  console.error(`FAILED ${failures.length} of ${checks} checks\n`);
  for (const f of failures) console.error(`  - ${f}`);
  console.error('');
  process.exit(1);
}
console.log(`PASSED all ${checks} checks · ${cfg.name} ${version} · ${pages.length} pages`);
