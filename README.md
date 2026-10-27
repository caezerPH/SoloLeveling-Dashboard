# SoloLeveling Dashboard

A gated component library. Browse 969 UI components and motion cards, copy the code
or the prompt for one, and leave an audit trail doing it.

**There is no component code in this repository.** The pages here are a shell. Every
snippet lives in Postgres behind row-level security and reaches the browser one at a
time, on an authenticated request, after the fetch has been logged. Cloning this repo
gets you a login screen and nothing behind it.

## Why it is built this way

The obvious way to protect a component library is to disable right-click. That stops
nobody — `Ctrl+U`, DevTools, the network tab, Save-As and `curl` all walk straight
past it, and it only inconveniences the people who are allowed to be there.

The defensible question is not *can a viewer read the code* — a viewer must read the
code, that is what the Copy button is for. It is *can a viewer read all of it at
once*. So:

| Table | Who can read it | Why |
|---|---|---|
| `components` | any signed-in user, in full | Names, sections, dependency lists. Metadata, not the deliverable |
| `component_sources` | **admins only** | The actual code. A viewer has no select policy at all, not a narrow one |
| `copy_log` | your own rows; admins see all | Who fetched what, when |

A viewer reaches a snippet only through `get_source(id, kind)` — one component per
call, rate limited to 150 an hour, and written to the audit log *before* it returns.
Bulk extraction is therefore 942 separate calls under a named account against a
ceiling, which is a thing you can watch and revoke, rather than one `select *`.

Accounts are issued, never self-served: signup and anonymous sign-in are both
disabled at the project level, so possession of the public anon key buys nothing.

## Layout

```
index.html        the portal shell
config.js         project URL and the anon key (both public by design)
sql/01-schema.sql tables, policies, the get_source gate, the audit view
tools/import.py   one-off loader, run locally, reads credentials from a .env
                  that is outside this repository
```

## Setup

**1. Database.** Paste `sql/01-schema.sql` into the Supabase SQL editor and run it.
It is idempotent. Then:

```sql
alter view public.copy_activity set (security_invoker = on);
```

That line is not optional. A Postgres view runs as its owner unless told otherwise,
which would let any viewer read every account's email and copy history straight past
the policies above it.

**2. Lock the door.** Authentication → Sign In / Providers → turn **off** both
*Allow new users to sign up* and *Allow anonymous sign-ins*. Create accounts by hand
under Authentication → Users, with **Auto Confirm User** ticked.

Every new account lands as `viewer`. Promote deliberately:

```sql
insert into public.profiles (id, email, role)
select id, email, 'admin' from auth.users where email = 'you@example.com'
on conflict (id) do update set role = 'admin';
```

**3. Data.** `py -3 tools/import.py` for a dry run, then `--apply`. It needs
`SUPABASE_URL` and `SUPABASE_SERVICE_KEY` in a `.env` *outside* this folder. The
service key bypasses every policy in the project — it never belongs in a repository,
a browser bundle or a chat window.

**4. Verify, do not assume.** With no session at all, these must all come back empty
or refused:

```bash
curl -s "$URL/rest/v1/components?select=id&limit=1"        -H "apikey: $ANON"  # []
curl -s "$URL/rest/v1/component_sources?select=code&limit=1" -H "apikey: $ANON"  # []
curl -s -X POST "$URL/rest/v1/rpc/get_source" -H "apikey: $ANON" \
     -H 'Content-Type: application/json' -d '{"cid":"x","kind":"code"}'          # 401
```

## Licensing and attribution

**Full notices: [NOTICE.md](NOTICE.md). This repository's own code: [LICENSE](LICENSE), MIT.**

Most of what this portal serves was made by other people. **No ownership or copyright
is claimed over any of it** — credit belongs to each author, and `NOTICE.md` names
every one with its licence and a link to the authoritative text.

The short version:

| | |
|---|---|
| **Component DB** (226) and **Builders** (27) | Written in-house. The only items this project has a claim over |
| **Motion** (716) | BrewedOps Motion Library, under its own free licence — commercial and client use permitted, no attribution required. Credited anyway, because the work is theirs |
| **three.js** `0.186.1`, **Lenis** `1.3.26`, **supabase-js** `2.45.4` | MIT, each to its own authors |
| **GSAP** `3.15.0` | GreenSock standard licence. Free on a site or app; **not** inside a no-code animation builder, which is why the builders here use no GSAP |
| **Geist** / **Geist Mono** | SIL OFL 1.1, © Vercel |

Provenance is stored per component in the database — `licence` and `origin` columns —
rather than buried in a footer, so nothing is served without it.

The BrewedOps licence permits *use* and forbids *republishing the collection as your
own*. This portal serves those cards as a working set alongside in-house components,
with their origin recorded per row; it is not a rebadged copy of that library, and
the BrewedOps name and logo are not used as branding here.
