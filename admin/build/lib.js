'use strict';
// Shared helpers for the build and the validator, so the two can never disagree
// about what a page is or what URL it lives at.

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');

// Directories that hold machinery or metadata rather than published pages.
const SKIP_DIRS = new Set(['.git', '.github', 'node_modules', 'admin', 'assets']);

function readConfig() {
  const cfg = JSON.parse(fs.readFileSync(path.join(__dirname, 'site.json'), 'utf8'));
  if (!/\/$/.test(cfg.baseUrl)) {
    throw new Error('site.json: baseUrl must end with a trailing slash');
  }
  return cfg;
}

function readVersion() {
  const v = fs.readFileSync(path.join(ROOT, 'VERSION'), 'utf8').trim();
  if (!/^v\d+\.\d+\.\d+$/.test(v)) {
    throw new Error(`VERSION must look like v1.2.3, got "${v}"`);
  }
  return v;
}

// Every published HTML page, as a repo-relative POSIX path, sorted.
function listPages(dir = ROOT, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const abs = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (SKIP_DIRS.has(entry.name)) continue;
      listPages(abs, out);
    } else if (entry.isFile() && entry.name.endsWith('.html')) {
      out.push(path.relative(ROOT, abs).split(path.sep).join('/'));
    }
  }
  return out.sort();
}

// The canonical URL a page must claim. Directory indexes get the clean
// directory form, because that is the URL GitHub Pages actually serves.
function urlFor(rel, baseUrl) {
  if (rel === 'index.html') return baseUrl;
  if (rel.endsWith('/index.html')) return baseUrl + rel.slice(0, -'index.html'.length);
  return baseUrl + rel;
}

function buildSitemap(pages, cfg) {
  const exempt = new Set(cfg.sitemapExempt || []);
  const locs = pages
    .filter((p) => !exempt.has(p))
    .map((p) => `  <url><loc>${urlFor(p, cfg.baseUrl)}</loc></url>`);
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    ...locs,
    '</urlset>',
    '',
  ].join('\n');
}

function buildRobots(cfg) {
  return ['User-agent: *', 'Allow: /', '', `Sitemap: ${cfg.baseUrl}sitemap.xml`, ''].join('\n');
}

// Apply the version stamp to one page's source. Returns the new text.
function stamp(html, version) {
  return html
    .replace(
      /(<meta\s+name="site-version"\s+content=")[^"]*(")/,
      `$1${version}$2`
    )
    .replace(
      /(<span\s+data-site-version>)[^<]*(<\/span>)/g,
      `$1${version}$2`
    );
}

module.exports = { ROOT, readConfig, readVersion, listPages, urlFor, buildSitemap, buildRobots, stamp };
