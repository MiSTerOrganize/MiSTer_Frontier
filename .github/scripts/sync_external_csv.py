#!/usr/bin/env python3
"""Sync external_files.csv RBF date suffixes from per-core repos.

Polls each per-core repo's _Other/ directory via the GitHub API, finds the
latest dated RBF filename (e.g. PICO-8_20260615.rbf), and rewrites the
matching rows in external_files.csv to use the new path + URL.

Idempotent: if the CSV already references the latest RBF, no changes are
written. Exit code 0 either way.

Per-core repos handled:
  MiSTer_PICO-8         → _Other/PICO-8_*.rbf
  MiSTer_OpenBOR_4086   → _Other/OpenBOR_4086_*.rbf
  MiSTer_OpenBOR_7533   → _Other/OpenBOR_7533_*.rbf

Run from MiSTer_Frontier's repo root:

    python3 .github/scripts/sync_external_csv.py
"""

from __future__ import annotations

import os
import re
import sys
import urllib.request
import json
from pathlib import Path

ORG = "MiSTerOrganize"
PER_CORE_REPOS = [
    "MiSTer_PICO-8",
    "MiSTer_OpenBOR_4086",
    "MiSTer_OpenBOR_7533",
]
CSV_PATH = Path("external_files.csv")
DATED_RBF_RE = re.compile(r"^(?P<stem>.+?)_(?P<date>\d{8})\.rbf$")


def gh_api(url: str) -> list[dict]:
    """GET a GitHub API endpoint, return parsed JSON."""
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "MiSTer-Frontier-CSV-Sync",
            **(
                {"Authorization": f"token {os.environ['GITHUB_TOKEN']}"}
                if os.environ.get("GITHUB_TOKEN")
                else {}
            ),
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def latest_rbf_in_repo(repo: str) -> str | None:
    """Return the newest-dated RBF filename in `_Other/` of `repo`, or None."""
    entries = gh_api(f"https://api.github.com/repos/{ORG}/{repo}/contents/_Other")
    rbfs = [
        e["name"]
        for e in entries
        if e.get("type") == "file" and DATED_RBF_RE.match(e["name"])
    ]
    if not rbfs:
        return None
    # Sort by date suffix (8 digits, sorts correctly as string)
    return sorted(rbfs, key=lambda f: DATED_RBF_RE.match(f).group("date"))[-1]


def update_csv_for_repo(csv_text: str, repo: str, latest_rbf: str) -> tuple[str, bool]:
    """Update CSV rows that reference `repo`'s `_Other/*.rbf` to use `latest_rbf`.

    Returns (new_csv_text, changed_flag).
    """
    new_lines = []
    changed = False
    repo_url_marker = f"/{ORG}/{repo}/main/_Other/"
    for line in csv_text.splitlines():
        # Match CSV rows that reference this repo's _Other/ RBF
        if repo_url_marker in line and ".rbf" in line:
            parts = line.split(",")
            if len(parts) >= 5:
                new_path = f"_Other/{latest_rbf}"
                new_url = re.sub(
                    rf"(/{ORG}/{repo}/main/_Other/)[^,]+\.rbf",
                    rf"\g<1>{latest_rbf}",
                    parts[1],
                )
                if parts[0] != new_path or parts[1] != new_url:
                    parts[0] = new_path
                    parts[1] = new_url
                    line = ",".join(parts)
                    changed = True
        new_lines.append(line)
    return "\n".join(new_lines) + "\n", changed


def main() -> int:
    if not CSV_PATH.exists():
        print(f"ERROR: {CSV_PATH} not found in cwd; run from repo root", file=sys.stderr)
        return 1

    csv_text = CSV_PATH.read_text()
    any_changed = False

    for repo in PER_CORE_REPOS:
        try:
            latest = latest_rbf_in_repo(repo)
        except Exception as e:
            print(f"WARN: could not list {repo}/_Other ({e}); skipping", file=sys.stderr)
            continue

        if latest is None:
            print(f"WARN: no dated RBFs in {repo}/_Other; skipping", file=sys.stderr)
            continue

        csv_text, changed = update_csv_for_repo(csv_text, repo, latest)
        if changed:
            print(f"  {repo}: CSV updated → {latest}")
            any_changed = True
        else:
            print(f"  {repo}: already current ({latest})")

    if any_changed:
        CSV_PATH.write_text(csv_text)
        print("CSV written.")
    else:
        print("No changes — CSV is in sync with all per-core repos.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
