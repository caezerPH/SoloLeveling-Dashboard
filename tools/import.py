"""Push the library into Supabase: 969 catalogue rows, 942 snippet bodies.

    py -3 _portal/import.py              # dry run -- counts and samples, writes nothing
    py -3 _portal/import.py --apply      # actually write

Reads SUPABASE_URL and SUPABASE_SERVICE_KEY from the studio-root .env. The service
key bypasses every RLS policy, which is exactly why it lives there and never in the
repo, never in the browser bundle, and never in a chat window. This script is the
only thing that should ever hold it.

Idempotent: every write is an upsert keyed on the primary key, so re-running after
adding a component updates rather than duplicates.

Standard library only -- no pip install, nothing to pin.

What goes where, and why:
  components         the catalogue a signed-in user may read in full. Names,
                     sections, dependency list, licence line, provenance. None of
                     it is the deliverable.
  component_sources  the code and the prompt. Admin-only at the RLS level; a
                     viewer reaches these one at a time through get_source().

The 27 builders carry no source row. They are whole interactive tools, not
snippets -- the portal links out to the builder rather than offering a copy button,
which is also how the local dashboard treats them.
"""

import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

# parents[2] because this file sits at _portal/tools/import.py -- tools, then
# _portal, then the library itself.
LIB = Path(__file__).resolve().parents[2]              # Website library Samples
STUDIO = LIB.parent                                    # Claude Main Project
APPLY = "--apply" in sys.argv


# ---------------------------------------------------------------------------
# credentials
# ---------------------------------------------------------------------------

def load_env():
    env = {}
    f = STUDIO / ".env"
    if not f.exists():
        sys.exit(f"no .env at {f} -- see the step 3 instructions")
    for line in f.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


ENV = load_env()
URL = ENV.get("SUPABASE_URL", "").rstrip("/")
KEY = ENV.get("SUPABASE_SERVICE_KEY", "")
missing = [k for k, v in (("SUPABASE_URL", URL), ("SUPABASE_SERVICE_KEY", KEY)) if not v]
if missing:
    sys.exit("missing from .env: " + ", ".join(missing))

# Never print the key. Print enough to prove the right one was picked up.
try:
    import base64
    payload = KEY.split(".")[1]
    claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
    if claims.get("role") != "service_role":
        sys.exit(f"that key has role '{claims.get('role')}' -- the import needs the "
                 "service_role key, not the anon key")
    print(f"  key   role={claims['role']} ref={claims['ref']}")
except SystemExit:
    raise
except Exception:
    print("  key   could not decode -- continuing, the API will reject it if wrong")
print(f"  url   {URL}")


def post(table, rows, on_conflict):
    """Upsert a batch. PostgREST merges duplicates when told to."""
    body = json.dumps(rows, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        f"{URL}/rest/v1/{table}?on_conflict={on_conflict}",
        data=body, method="POST",
        headers={
            "apikey": KEY,
            "Authorization": f"Bearer {KEY}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates,return=minimal",
        })
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:600]
        sys.exit(f"\n  HTTP {e.code} writing {table}\n  {detail}")


# ---------------------------------------------------------------------------
# read what the live pages read
# ---------------------------------------------------------------------------

def brace_match(src, start):
    i = min(p for p in (src.find("{", start), src.find("[", start)) if p != -1)
    open_c = src[i]
    close_c = "}" if open_c == "{" else "]"
    depth, in_str, esc = 0, None, False
    for j in range(i, len(src)):
        c = src[j]
        if in_str:
            if esc: esc = False
            elif c == "\\": esc = True
            elif c == in_str: in_str = None
            continue
        if c in "\"'": in_str = c
        elif c == open_c: depth += 1
        elif c == close_c:
            depth -= 1
            if depth == 0:
                return src[i:j + 1]
    raise ValueError("unbalanced literal")


raw = (LIB / "menu-index.js").read_text(encoding="utf-8")
MENU = json.loads(raw.split("window.LIB = ", 1)[1].rsplit(";", 1)[0].strip())
LIBS = {l["k"]: l for l in MENU["libs"]}

# The DB's hand-authored preview sketches. These are a drawing of the component,
# not the component, so they are safe to hold in the catalogue and render in a grid
# without handing anybody the code.
dbsrc = (LIB / "_studio-builds/_db/index.html").read_text(encoding="utf-8")
DEMOS = {it["id"]: it.get("demo")
         for it in json.loads(brace_match(dbsrc, dbsrc.index("const D = ")))["items"]}

SNIPPETS = {
    "db": LIB / "_studio-builds/_db/snippets",
    "brewedops": LIB / "_brewedops/snippets",
}
ORIGIN = {
    "db": "LGG Media studio -- written in-house",
    "builders": "LGG Media studio -- written in-house",
    "brewedops": "BrewedOps motion library -- free licence, no attribution required",
}
DISPLAY_LIBRARY = {"db": "db", "builders": "builders", "brewedops": "motion"}

catalogue, sources = [], []
missing_files = []

for it in MENU["items"]:
    key = it["l"]
    lib = LIBS[key]
    sid = it["i"]
    code = prompt = None

    if key in SNIPPETS:
        h = SNIPPETS[key] / f"{sid}.html"
        t = SNIPPETS[key] / f"{sid}.txt"
        if h.exists():
            code = h.read_text(encoding="utf-8")
            prompt = t.read_text(encoding="utf-8") if t.exists() else None
        else:
            missing_files.append(sid)
    elif key == "builders":
        # A builder is a whole self-contained tool, so its index.html IS its source.
        # Previously these carried an open_url instead, which pointed at a path that
        # exists on the studio machine and nowhere else -- a guaranteed 404 the
        # moment the portal was deployed. Serving it through get_source() removes
        # the dead link and puts the builders behind the same gate as everything
        # else. They are ours, so there is no licence question in storing them.
        h = LIB / "_studio-builds" / sid / "index.html"
        if h.exists():
            code = h.read_text(encoding="utf-8")
        else:
            missing_files.append(sid)

    # The key is namespaced because component ids are unique within a library and
    # not across them: 'pricing-table' is both a studio builder and a motion card.
    # Unnamespaced, the upsert merged the two and lost a row without erroring.
    catalogue.append({
        "id": f"{DISPLAY_LIBRARY[key]}:{sid}",
        "slug": sid,
        "library": DISPLAY_LIBRARY[key],
        "name": it["n"],
        "section": it.get("s"),
        "descr": it.get("d"),
        "deps": it.get("libs") or [],
        "ship": "yes" if key in ("db", "builders") else "cond",
        "licence": lib["lic"],
        "origin": ORIGIN[key],
        "preview_html": DEMOS.get(sid),
        "open_url": None,          # nothing links out any more -- see above
        "has_source": code is not None,
        "has_prompt": prompt is not None,
        "code_bytes": len(code.encode("utf-8")) if code else None,
    })
    if code is not None:
        sources.append({"component_id": f"{DISPLAY_LIBRARY[key]}:{sid}",
                        "code": code, "prompt": prompt})

# ---------------------------------------------------------------------------
# report, then write
# ---------------------------------------------------------------------------

from collections import Counter

# A duplicate key here would be silently merged by the upsert, which is exactly how
# a row went missing the first time. Fail loudly instead.
ids = [c["id"] for c in catalogue]
dupes = {i for i in ids if ids.count(i) > 1}
if dupes:
    sys.exit(f"  duplicate component ids -- would silently merge: {sorted(dupes)}")

print()
print(f"  catalogue rows   {len(catalogue):5}  " +
      "  ".join(f"{k}={v}" for k, v in Counter(c["library"] for c in catalogue).items()))
print(f"  source rows      {len(sources):5}  "
      f"{sum(len(s['code']) for s in sources) / 1048576:.1f} MB of code, "
      f"{sum(len(s['prompt'] or '') for s in sources) / 1048576:.1f} MB of prompts")
print(f"  with a preview   {sum(1 for c in catalogue if c['preview_html']):5}")
print(f"  with a prompt    {sum(1 for c in catalogue if c['has_prompt']):5}")
print(f"  no source row    {sum(1 for c in catalogue if not c['has_source']):5}")
if missing_files:
    print(f"  MISSING ON DISK  {len(missing_files):5}  {missing_files[:6]}")

if not APPLY:
    print("\n  dry run -- nothing written. Re-run with --apply")
    sys.exit(0)

print("\n  writing...")
t0 = time.time()

for i in range(0, len(catalogue), 200):
    post("components", catalogue[i:i + 200], "id")
    print(f"    catalogue {min(i + 200, len(catalogue)):5}/{len(catalogue)}")

# Smaller batches: a source row can be 30 KB and PostgREST has a request ceiling.
for i in range(0, len(sources), 20):
    post("component_sources", sources[i:i + 20], "component_id")
    if (i // 20) % 10 == 0 or i + 20 >= len(sources):
        print(f"    sources   {min(i + 20, len(sources)):5}/{len(sources)}")

print(f"\n  done in {time.time() - t0:.1f}s")
print("  verify in the SQL editor:")
print("    select library, count(*) from public.components group by library;")
print("    select count(*) from public.component_sources;")
