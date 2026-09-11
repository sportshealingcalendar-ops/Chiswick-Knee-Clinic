# Chiswick Knee Clinic: outstanding work

Site: https://chiswickkneeclinic.com/
Live version: v0.2.0
Deployed: 11 September 2026
Repository: sportshealingcalendar-ops/Chiswick-Knee-Clinic
Deploy branch: dev

Three tasks remain. None block the site from running. All three affect how it is judged.

---

## Current state

| Area | Status |
|---|---|
| Home page | Live and correct |
| Custom domain | Live, apex, certificate issued |
| Phone, email, addresses, maps | Working |
| Links to the three sister sites | Working |
| Booking form | Broken |
| Legal pages | Live, draft text |
| Treatments page | Old content, hidden |
| Surgeon portrait | Placeholder |

---

## Task 1. Booking form

**Status:** broken in production.

**What happens now.** A patient fills in the form and gets an error. The error gives the phone number, so the lead is not lost outright. Most people will not phone.

**Why it is broken.** The form needs an access key from Web3Forms. The file still holds the text `REPLACE_WITH_WEB3FORMS_ACCESS_KEY`.

### The data problem behind it

The form collects five fields:

1. Full name
2. Date of birth
3. Phone number
4. Email
5. Reason for appointment

The fifth field is health information about a named person. UK GDPR calls this special category data. It carries the strictest rules of any personal data.

Web3Forms is a third party. Handing them special category data needs a written processor contract under Article 28. A free account with click-through terms is not that contract.

Two further points:

- The site's own privacy policy promises that service providers are held to that standard. Today that promise is not met.
- The page says "We never share them with third parties" directly under the submit button. Web3Forms is a third party. The sentence is wrong as built.

### Three ways forward

**Option A. Build our own endpoint on AWS.**

- Route: form posts to API Gateway, then Lambda, then SES sends the email
- Data stays in one AWS account under the AWS processor terms
- Nothing stored, so there is no database to breach
- Cost: free or close to it at clinic volumes
- Build time: about a day
- Trade-off: infrastructure we own and must maintain

**Option B. Pay a UK healthcare form provider.**

- They sign a proper processor contract
- Cost: monthly fee
- Build time: hours
- Trade-off: ongoing cost, less control

**Option C. Cut the form back, launch now, fix later.**

- Keep name, phone and email only
- Drop date of birth and the free text reason
- Copy becomes "we will call you to take details"
- No health data reaches a third party
- Build time: under an hour
- Trade-off: fewer conversions

### Regardless of option

Rewrite the line "We never share them with third parties". It is inaccurate under every option, including our own AWS endpoint.

**Recommendation:** Option A. Moving the form costs a day. An ICO complaint about a clinic mishandling health data costs the local reputation we are trying to build.

---

## Task 2. Legal page placeholders

**Status:** live, with draft text visible.

Three pages are published and linked from the footer. Each shows bracketed placeholder text to anyone who opens it. Each carries `noindex`, so search engines skip them.

### What needs filling

**Privacy policy**
- Last updated date
- Record retention period, stated twice

**Terms and conditions**
- Last updated date
- Consultation fees, self pay options, accepted insurers

**Cookie policy**
- Last updated date
- Analytics provider, if any
- Consent tool name, if any
- Any other embedded services

### What is already correct

These pages are not starting from nothing. They already carry:

- Sports Healing Ltd, company number 05540087
- ICO registration ZA005873
- Registered office address
- The correct UK GDPR lawful bases, Article 6 and Article 9

### Steps

1. Collect the answers above from the practice
2. Have a data protection professional review the wording
3. Fill the placeholders
4. Switch all three pages from `noindex` to `index, follow`
5. Add all three to the sitemap

Steps 4 and 5 are one commit. They should happen together, and only once the text is signed off.

**Effort:** an hour of edits, plus whatever the review takes.

---

## Task 3. Treatments page

**Status:** old content, hidden from visitors.

The file `treatments/index.html` still holds the original scaffold page. It does not match the new design. Nothing links to it. It is excluded from the sitemap and from the orphan check.

It is still reachable by anyone who types the URL.

### What it should become

A treatments page built from the content on `chinmaygupte.com/knee-treatments/`, including its sub-pages, styled to match the new home page.

### Blocker

The build environment cannot reach chinmaygupte.com. The content has to be supplied by hand.

### Steps

1. Export or copy the treatments page and its sub-pages
2. Decide which sub-pages belong on this site
3. Rebuild the page in the new design
4. Link it from the main navigation
5. Remove the two exclusions in `admin/build/site.json`
6. Rebuild so the sitemap picks it up

**Effort:** half a day once the content arrives.

---

## Also outstanding

**Surgeon portrait.** Still a grey placeholder card reading "PHOTO PENDING". A photo was pasted into chat rather than attached as a file, so it could not be saved. Needs re-sending as a file attachment. Portrait orientation suits the layout, which expects 716 by 896 pixels.

**Social share image.** Placeholder at `assets/og-chiswick-knee-clinic.jpg`. Links shared to WhatsApp or LinkedIn show a grey card. Needs a real image at 1200 by 630 pixels.

---

## Suggested order

| Priority | Task | Why first |
|---|---|---|
| 1 | Surgeon portrait | Most visible. Fastest fix. Needs only the file |
| 2 | Booking form | Every failed submission is a lost patient |
| 3 | Legal placeholders | Visible to anyone who clicks the footer |
| 4 | Treatments page | Hidden, so it costs nothing while it waits |

---

## How to ship any of these

Each change is one release:

```sh
admin/build/release.sh --patch "what changed"
```

That bumps the version, rebuilds, runs 59 checks, commits, pushes to `dev`, and waits for the live site to serve the new version. Nothing ships if a check fails.

Rollback is one command:

```sh
git revert <commit> && git push origin dev
```

The pages that were live before the rebuild are kept in `admin/backup/`.
