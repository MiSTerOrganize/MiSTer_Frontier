#!/usr/bin/env python3
"""Verify that db.json is built from, and agrees with, what is actually on main.

WHY
---
`build_db.py` FETCHES the raw.githubusercontent URLs in external_files.csv. The
CDN is edge-cached, so a build started moments after a push can read the
PREVIOUS bytes for a file that push just replaced -- and db.json then ships a
stale hash. `update_all` rejects the mismatched file and DELETES it, leaving a
broken core on the user's card (measured 2026-08-24; the 2026-05-26 failure).

The per-core repos gate their DISPATCH on propagation, which stops the pointless
rebuild. That gate runs on the producer's runner though, and raw.github is
cached per-POP, so it cannot prove what THIS runner will read. These two checks
can, because they run here:

  --pre   before the build: for every URL the combiner will fetch, does the CDN
          serve what git actually has? Same runner, same edge, moments before
          the real fetch. Retries while propagation catches up.

  --post  after the build: does every entry in the PUBLISHED db.json match git?
          This is the deliverable itself, so it also catches anything --pre
          cannot -- a push landing mid-build, or the builder mis-transcribing.

"What git actually has" means the GitHub API contents endpoint, which reads git
objects. Never the CDN: comparing the CDN to itself would confirm nothing.

EXIT CODES (distinct on purpose -- a caller testing `rc != 0` cannot tell a
broken invocation from a real refusal)
  0  everything agrees
  1  disagreement, or gave up waiting
  2  usage / environment error
"""
import argparse
import csv
import hashlib
import io
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

CSV_PATH = "external_files.csv"
RAW_PREFIX = "https://raw.githubusercontent.com/"
API = "https://api.github.com/repos/%s/%s/contents/%s?ref=%s"


def die(msg, code=2):
    print("::error::verify_db_currency: %s" % msg)
    sys.exit(code)


def fetch(url, headers=None, timeout=60):
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def md5(b):
    return hashlib.md5(b).hexdigest()


def parse_csv(path):
    """-> [(mister_path, raw_url, owner, repo, branch, repo_path)]"""
    if not os.path.exists(path):
        die("%s not found (run from the repo root)" % path)
    rows = []
    with io.open(path, encoding="utf-8", newline="") as fh:
        for i, row in enumerate(csv.reader(fh)):
            if i == 0 or not row or not row[0].strip():
                continue          # header / blank
            if len(row) < 2:
                die("%s line %d: fewer than 2 columns" % (path, i + 1))
            mister_path, url = row[0].strip(), row[1].strip()
            if not url.startswith(RAW_PREFIX):
                die("%s: URL is not a raw.githubusercontent URL: %s"
                    % (mister_path, url))
            rest = url[len(RAW_PREFIX):].split("/")
            if len(rest) < 4:
                die("%s: cannot parse owner/repo/branch/path from %s"
                    % (mister_path, url))
            owner, repo, branch = rest[0], rest[1], rest[2]
            rows.append((mister_path, url, owner, repo, branch,
                         "/".join(rest[3:])))
    if not rows:
        die("%s has no data rows" % path)
    return rows


def authoritative(owner, repo, branch, path, token):
    """md5 of what git has -- the API contents endpoint, never the CDN."""
    headers = {"Accept": "application/vnd.github.raw",
               "User-Agent": "MiSTer_Frontier-verify"}
    if token:
        headers["Authorization"] = "Bearer %s" % token
    quoted = urllib.parse.quote(path)
    return md5(fetch(API % (owner, repo, quoted, branch), headers))


def cmd_pre(args, rows, token):
    print("pre-build: %d URL(s); comparing the CDN against git" % len(rows))

    # The authoritative side cannot change while we wait, so fetch it once --
    # retrying it would just burn API quota.
    want = {}
    for mister_path, _url, owner, repo, branch, repo_path in rows:
        try:
            want[mister_path] = authoritative(owner, repo, branch, repo_path,
                                              token)
        except urllib.error.HTTPError as e:
            die("%s: git says HTTP %s for %s/%s@%s:%s"
                % (mister_path, e.code, owner, repo, branch, repo_path))
        except Exception as e:                                  # noqa: BLE001
            die("%s: cannot read authoritative content (%s)" % (mister_path, e))

    for attempt in range(1, args.tries + 1):
        lagging = []
        for mister_path, url, _o, _r, _b, _p in rows:
            try:
                got = md5(fetch(url))
            except Exception:                                   # noqa: BLE001
                got = "fetch-failed"
            if got != want[mister_path]:
                lagging.append((mister_path, got, want[mister_path]))
        if not lagging:
            print("all %d URL(s) serve what git has (attempt %d)"
                  % (len(rows), attempt))
            return 0
        print("attempt %d/%d: %d not propagated"
              % (attempt, args.tries, len(lagging)))
        for p, got, w in lagging:
            print("    %-46s cdn=%s git=%s" % (p, got[:12], w[:12]))
        if attempt < args.tries:
            time.sleep(args.nap)

    print("::error::The CDN still serves stale bytes for %d file(s) after "
          "~%d s. NOT building: build_db.py reads these URLs, so db.json would "
          "record stale hashes and update_all would DELETE the mismatched file "
          "on every user's card. The previous db.json stays in place; the "
          "daily cron will retry."
          % (len(lagging), args.tries * args.nap))
    return 1


def load_published_db(source):
    """The published artifact, so we check the deliverable and not a copy."""
    if source == "branch":
        import subprocess
        # Fetch into FETCH_HEAD, never into a local branch: build_db.py leaves
        # the checkout ON the db branch, and git refuses to fetch into the
        # branch that is currently checked out.
        subprocess.run(["git", "fetch", "-q", "origin", "db"], check=True)
        blob = subprocess.run(["git", "show", "FETCH_HEAD:db.json.zip"],
                              check=True, stdout=subprocess.PIPE).stdout
    else:
        blob = io.open(source, "rb").read()
    z = zipfile.ZipFile(io.BytesIO(blob))
    names = [n for n in z.namelist() if n.endswith(".json")]
    if len(names) != 1:
        die("db.json.zip holds %d .json entries, expected 1" % len(names))
    return json.loads(z.read(names[0]).decode("utf-8"))


def cmd_post(args, rows, token):
    db = load_published_db(args.db)
    files = db.get("files") or {}
    if not files:
        die("published db.json has no files", 1)

    by_path = {r[0]: r for r in rows}
    bad, unknown = [], []

    for key in sorted(files):
        # the downloader's base-path convention leaves a leading '|' on most
        rel = key.lstrip("|")
        row = by_path.get(rel)
        if row is None:
            unknown.append(rel)
            continue
        _p, _url, owner, repo, branch, repo_path = row
        try:
            want = authoritative(owner, repo, branch, repo_path, token)
        except Exception as e:                                  # noqa: BLE001
            die("%s: cannot read authoritative content (%s)" % (rel, e), 1)
        got = files[key].get("hash")
        mark = "OK " if got == want else "STALE"
        print("  %s %-46s db=%s git=%s"
              % (mark, rel, (got or "?")[:12], want[:12]))
        if got != want:
            bad.append(rel)

    missing = sorted(set(by_path) - {k.lstrip("|") for k in files})

    if unknown:
        print("::error::db.json ships %d file(s) with no external_files.csv "
              "row, so their content was never verified: %s. Add them to the "
              "CSV, or to FINDER_IGNORE if they should not ship."
              % (len(unknown), ", ".join(unknown)))
    if missing:
        print("::error::%d CSV row(s) are absent from db.json -- users will "
              "not receive them: %s" % (len(missing), ", ".join(missing)))
    if bad:
        print("::error::db.json records a STALE hash for %d file(s): %s. "
              "update_all would reject and DELETE each on every user's card. "
              "The pre-build gate passed, so this is NOT ordinary propagation "
              "lag -- suspect a push that landed mid-build. Re-run this "
              "workflow; if it repeats, stop and investigate."
              % (len(bad), ", ".join(bad)))

    if bad or unknown or missing:
        return 1
    print("published db.json matches git for all %d file(s)." % len(files))
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--pre", action="store_true",
                   help="before the build: CDN vs git, with retries")
    g.add_argument("--post", action="store_true",
                   help="after the build: published db.json vs git")
    ap.add_argument("--tries", type=int, default=15)
    ap.add_argument("--nap", type=int, default=10)
    ap.add_argument("--csv", default=CSV_PATH)
    ap.add_argument("--db", default="branch",
                    help="'branch' (default) or a path to a db.json.zip")
    args = ap.parse_args()

    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    rows = parse_csv(args.csv)
    return cmd_pre(args, rows, token) if args.pre else cmd_post(args, rows,
                                                                token)


if __name__ == "__main__":
    sys.exit(main())
