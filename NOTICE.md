# Third-party notices and attribution

This portal is a front end. Most of what it serves was made by other people, and
**no ownership or copyright is claimed over any of it.** Credit for each item below
belongs to its author. Everything is used under the licence stated, and each entry
links to the authoritative text rather than paraphrasing it.

If something here is wrong, or an author would prefer different wording, raise an
issue and it will be corrected.

---

## What the portal itself loads

| | |
|---|---|
| **supabase-js** `2.45.4` | MIT — © Supabase Inc. — <https://github.com/supabase/supabase-js/blob/master/LICENSE> |

That is the whole runtime dependency list. The page is otherwise plain HTML, CSS and
JavaScript with no framework and no build step.

**Vite and React are not used by this project** and are deliberately not listed. The
studio uses both elsewhere; naming them here would assert a dependency that does not
exist.

---

## What the catalogue serves

### BrewedOps Motion Library — 716 cards

Mirrored from <https://brewedops.cloud/motionlibrary/> under the library's own free
licence, read in full at `/motionlibrary/legal/license/`.

That licence permits use in personal projects, client work and commercial products,
including copying, modifying and combining the cards, and shipping them in sites, web
apps, mobile apps and client templates. **No attribution is required** — it is given
here anyway, because the work is theirs.

The licence prohibits republishing the library as a collection of one's own — a
component pack, UI kit or animation library made mostly of these cards. This portal
serves them as a working set alongside components written in-house, with provenance
recorded per row in the database and surfaced in the catalogue, not as a BrewedOps
clone under another name.

The BrewedOps name and logo are **not** covered by that licence and are not used as
branding anywhere in this project. Product names, people, figures and logos appearing
inside the demo cards are invented by their authors.

A verbatim copy of the licence page, with its sha256, is kept with the local mirror
so the terms do not depend on that URL remaining reachable.

### Components and builders written in-house — 253

226 components and 27 builders written by LGG Media. These are the only items in the
catalogue this project has any claim over.

---

## Libraries used inside the cards

Pinned versions, as loaded by the cards that need them. 570 of the 716 cards use none
of these.

| | |
|---|---|
| **three.js** `0.186.1` — 74 cards | MIT — © 2010–2025 three.js authors — <https://github.com/mrdoob/three.js/blob/dev/LICENSE> |
| **GSAP** `3.15.0` — 59 cards | GreenSock standard licence — © GreenSock, Inc. — <https://gsap.com/community/standard-license/> |
| **Lenis** `1.3.26` — 14 cards | MIT — © darkroom.engineering — <https://github.com/darkroomengineering/lenis/blob/main/LICENSE> |

**On GSAP specifically.** GreenSock's standard licence permits use at no charge on
websites and in applications, including commercial ones. It does **not** permit
including GSAP in a product where the end user creates animations — a visual or
no-code animation builder. The builders in this catalogue are written without GSAP
for exactly that reason. Using a GSAP-based card on a page is covered; putting GSAP
inside one of the builders would not be.

---

## Typefaces

| | |
|---|---|
| **Geist** and **Geist Mono** | SIL Open Font License 1.1 — © Vercel, Inc. — <https://github.com/vercel/geist-font/blob/main/LICENSE.TXT> |

Loaded by all 716 motion cards via Google Fonts. The OFL permits commercial use and
embedding. The fonts are not redistributed by this repository.

---

## Screenshots

The catalogue shows generated preview images rather than live component code. For the
716 motion cards those are screenshots of BrewedOps' work, and they remain their
authors'. They are held in a **private** storage bucket and served only to
authenticated sessions through short-lived signed URLs — never published, never
indexed, and not reachable by an anonymous request.

---

## This repository's own code

The portal shell, the SQL schema and the import tooling are MIT licensed — see
[LICENSE](LICENSE). That covers this repository's code only. It does not extend to
any third-party work listed above, and it does not extend to the component
catalogue, which is served from a database rather than contained here.
