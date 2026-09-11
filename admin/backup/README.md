# Backup of the pages that were live before the rebuild

These are byte-for-byte copies of the pages GitHub Pages was serving at site
version v0.1.2, taken immediately before the new home page was dropped in.

| File | Was served at |
|---|---|
| `index.pre-v2.v0.1.2.html` | `/Chiswick-Knee-Clinic/` |
| `treatments-index.pre-v2.v0.1.2.html` | `/Chiswick-Knee-Clinic/treatments/` |
| `404.pre-v2.v0.1.2.html` | `/Chiswick-Knee-Clinic/404.html` |

`admin/` is excluded from the deployed site and from the page list the build
and validator walk, so nothing here is published or checked.

## To roll back the home page

```sh
cp admin/backup/index.pre-v2.v0.1.2.html index.html
node admin/build/build.js
node admin/build/validate.js
```

The git history is the other route: the state these files came from is commit
`f309d0c`.
