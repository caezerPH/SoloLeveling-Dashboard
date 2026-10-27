"""Upload generated thumbnails to Supabase Storage and point the catalogue at them.

    py -3 _portal/tools/upload-thumbs.py <folder> <library>        # dry run
    py -3 _portal/tools/upload-thumbs.py <folder> <library> --apply

<folder> holds <native-id>.jpg files. <library> is db | builders | motion, and is
what turns a filename into the namespaced component id the catalogue uses:

    thumbs/hero-split-reveal.jpg  ->  object  thumbs/motion/hero-split-reveal.jpg
                                  ->  row     motion:hero-split-reveal

The bucket is private. Nothing here grants public read -- the portal mints a
short-lived signed URL per session instead, because 716 of these are screenshots of
BrewedOps' work and their licence covers using the cards, not publishing the visuals.
"""

import json
import mimetypes
import sys
import urllib.error
import urllib.request
from pathlib import Path

LIB = Path(__file__).resolve().parents[2]
STUDIO = LIB.parent

if len(sys.argv) < 3:
    sys.exit(__doc__)
SRC = Path(sys.argv[1])
LIBRARY = sys.argv[2]
APPLY = "--apply" in sys.argv
if LIBRARY not in ("db", "builders", "motion"):
    sys.exit("library must be db, builders or motion")
if not SRC.is_dir():
    sys.exit(f"no such folder: {SRC}")

env = {}
for line in (STUDIO / ".env").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
URL = env["SUPABASE_URL"].rstrip("/")
KEY = env["SUPABASE_SERVICE_KEY"]
H = {"apikey": KEY, "Authorization": f"Bearer {KEY}"}


def req(method, path, data=None, headers=None, timeout=90):
    r = urllib.request.Request(URL + path, data=data, method=method,
                               headers={**H, **(headers or {})})
    try:
        with urllib.request.urlopen(r, timeout=timeout) as f:
            return f.status, f.read().decode("utf-8", "replace")[:300]
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")[:300]
    except Exception as e:
        return 0, str(e)[:200]


TYPES = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp",
         ".png": "image/png"}
files = sorted(f for f in SRC.iterdir() if f.suffix.lower() in TYPES)
total = sum(f.stat().st_size for f in files)
kinds = {}
for f in files:
    kinds[f.suffix.lower()] = kinds.get(f.suffix.lower(), 0) + 1
print("  " + ", ".join(f"{n} {ext}" for ext, n in sorted(kinds.items())))
print(f"  {len(files)} files, {total / 1048576:.1f} MB, avg {total / max(len(files),1) / 1024:.0f} KB")
print(f"  -> bucket thumbs/{LIBRARY}/   rows {LIBRARY}:<id>")

if not APPLY:
    print("\n  dry run -- nothing uploaded. Re-run with --apply")
    sys.exit(0)

# ---- upload ---------------------------------------------------------------
print("\n  uploading...")
failed, done = [], 0
for f in files:
    obj = f"{LIBRARY}/{f.name}"
    # x-upsert so a re-run replaces rather than erroring on a duplicate object.
    s, body = req("POST", f"/storage/v1/object/thumbs/{obj}", f.read_bytes(),
                  {"Content-Type": TYPES[f.suffix.lower()], "x-upsert": "true"})
    if s >= 300:
        failed.append((f.name, s, body[:90]))
    done += 1
    if done % 100 == 0:
        print(f"    {done}/{len(files)}")
print(f"    {done}/{len(files)}")
if failed:
    print(f"  UPLOAD FAILURES {len(failed)}:")
    for n, s, b in failed[:8]:
        print(f"    {n} HTTP {s} {b}")

# ---- point the catalogue at them ------------------------------------------
# One PATCH per row would be 716 requests, so these go up as a batched upsert.
#
# The payload has to carry library and name as well as id and thumb, even though
# only thumb is changing: an upsert is an INSERT with ON CONFLICT, Postgres builds
# and validates the candidate tuple BEFORE it checks the index, so a payload of
# {id, thumb} alone fails every NOT NULL column it omits. Reading the rows back
# first is one request and makes the batch legal.
print("\n  linking rows...")
ok = sorted(set(f.name for f in files) - set(n for n, _, _ in failed))

# Read direct rather than through req(), which truncates bodies for error display.
r = urllib.request.Request(
    URL + f"/rest/v1/components?select=id,library,name&library=eq.{LIBRARY}", headers=H)
with urllib.request.urlopen(r, timeout=90) as f:
    existing = {x["id"]: x for x in json.loads(f.read().decode())}
print(f"  {len(existing)} catalogue rows in '{LIBRARY}'")

rows, orphan = [], []
for n in ok:
    cid = f"{LIBRARY}:{Path(n).stem}"
    if cid in existing:
        rows.append({**existing[cid], "thumb": f"{LIBRARY}/{n}"})
    else:
        orphan.append(cid)
if orphan:
    print(f"  {len(orphan)} thumbnails have no catalogue row: {orphan[:5]}")

linked = 0
for i in range(0, len(rows), 200):
    batch = rows[i:i + 200]
    s, body = req("POST", "/rest/v1/components?on_conflict=id",
                  json.dumps(batch).encode("utf-8"),
                  {"Content-Type": "application/json",
                   "Prefer": "resolution=merge-duplicates,return=minimal"})
    if s >= 300:
        print(f"    HTTP {s} {body}")
        break
    linked += len(batch)
    print(f"    {linked}/{len(rows)}")

print(f"\n  {len(ok)} uploaded, {linked} rows linked")
print("  verify:  select count(*) from public.components where thumb is not null;")
