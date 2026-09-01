# Chiswick Knee Clinic

A static site, deployed to GitHub Pages by GitHub Actions from the `dev` branch.

The pipeline is modelled on the one [sgit.ai](https://sgit.ai/admin/index.html)
runs for its own site, including the three lessons that shaped it — each of
which was learned by getting it wrong first.

## Working on the site

```sh
node admin/build/build.js       # regenerate version stamps, sitemap.xml, robots.txt
node admin/build/validate.js    # the test suite
bash admin/build/selftest.sh    # prove the test suite still catches things
```

Pages are plain HTML with relative links. `admin/build/` holds the machinery
and is excluded from the deployed site.

## Releasing

```sh
admin/build/release.sh "shorter treatments copy"     # patch bump
admin/build/release.sh --minor "new conditions page"
```

That bumps `VERSION`, rebuilds, runs the validator, commits as
`site vX.Y.Z: <message>`, pushes, and then waits for the live site to actually
serve the new version. Nothing is pushed until the validator passes, so the
secret tripwire gates the git history and not just the deployment.

## The pipeline

`.github/workflows/deploy-pages.yml`, on every push to `dev`:

| Job | What it proves |
|---|---|
| `validate` | the tree builds, every check passes, and the checks themselves still fail on a broken tree |
| `tag-release` | if this commit claims a version, that claim is coherent — and it is tagged |
| `deploy` | the site is staged and published to GitHub Pages |
| `verify` | **a reader can actually load the new version** |

### Auto-tagging is driven by the commit subject

`admin/build/tag-release.sh` decides whether a push is a release by reading the
commit subject, not `VERSION`:

```
site v0.1.4: shorter treatments copy   -> a release: held to the full contract, tagged
fix a typo in the footer               -> an ordinary push: tagged nothing, published anyway
```

A commit that claims a version must satisfy all three of:

1. the subject and `VERSION` agree,
2. the version has not already shipped,
3. it is the immediate successor of the newest tag (`v0.1.1` → `v0.1.2`, `v0.2.0` or `v1.0.0`).

The asymmetry is the point. Deriving release-ness from `VERSION` alone means
every ordinary push after a release trips the "already tagged" check — and
because `deploy` requires `tag-release` to be *success or skipped*, a failure
there is not a missing tag, it is an outage. sgit.ai lost a day of publishing
to exactly that. **A missing tag is a bookkeeping gap; a blocked deploy is an
outage**, so only an explicit version claim is allowed to stop a publish.

Note for anyone debugging a rejected tag push: a workflow's `GITHUB_TOKEN`
cannot push a ref pointing at a commit whose tree carries a different version
of a workflow file. Tagging `HEAD` of the deploy branch is always safe.

### `verify` exists because green does not mean live

"Pushed successfully" and "a reader can load it" are different facts, separated
by a Pages job with its own failure modes. sgit.ai shipped two releases that
passed every check and reached nobody: `codeload` returned HTTP 429 for an
action download and the deploy died in *Set up job*, while the site served a
two-release-old page for forty minutes.

So every page carries `<meta name="site-version" content="vX.Y.Z">`, and the
last job polls the live URL with a cache-buster until that version appears —
up to 8 minutes, then it fails loudly. The origin's own answer is the only one
that counts.

Honest edges, in the same spirit: it detects a failed deploy but cannot repair
one (a 429 still needs a re-run); it checks the home page's stamp, so a partial
deploy would pass; and it taxes every release with up to 8 minutes of waiting.

### What the test suite checks

`admin/build/validate.js` — zero dependencies, so a registry outage cannot
break CI:

- **Structure** — required files exist; the entry point is lowercase `index.html`.
- **Generated files are current** — `sitemap.xml`, `robots.txt` and every
  version stamp match what the build would produce. "Did you re-run the build?"
  is a machine question.
- **Per page** — `lang`, a real `<title>`, a meta description, a canonical URL
  that matches the page's actual served path, the version stamp, and JSON-LD
  that parses.
- **Links** — every internal `href`/`src` resolves against the real file tree.
  Root-absolute links fail, because the site is served from a sub-path.
- **Reachability** — no orphan pages, and the sitemap lists every page. *A page
  nothing links to is unpublished, however green the deploy was.*
- **Content policy** — an advertising-claim tripwire for a UK medical site
  (outcome guarantees, superlatives). The list lives in `admin/build/site.json`.
- **Secret tripwire** — every git-tracked file is scanned for private keys,
  cloud credentials and provider tokens. Any literal listed in the gitignored
  `admin/build/.secret-strings` is also scanned for, so a known secret that
  reaches the tree fails the build by construction. *Honest edge: `validate.js`
  is excluded from the literal scan, because it holds the patterns themselves.*

`admin/build/selftest.sh` breaks a throwaway copy of the repository eighteen
ways — one at a time — and asserts each one is caught.

## Setup this repository needs once

- **Settings → Pages → Source: GitHub Actions.** Without this the deploy job
  fails and nothing publishes.
- **`baseUrl` in `admin/build/site.json`** currently points at the default
  `github.io` URL. For a custom domain, change it, add a `CNAME` file, and
  re-run the build — the canonical URLs and sitemap follow from that one value.
