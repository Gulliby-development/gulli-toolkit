"""Checks that every Gulli addon on main reached the player: released, in the bundle, in the index.

Usage: GH_TOKEN=... python3 tools/health/releases.py [--repo owner/name] [--out report.md]

For each Gulli-<Name> folder it compares the TOC version on main with
1. the newest release of its tag group (Core-v / <Name>-v): a version bumped on main more than
   RELEASE_HOURS ago and not released is a forgotten release;
2. the bundle (the `bundle` pre-release lists the tag of every addon in its notes);
3. the index (runeloader-index index.json): a release older than INDEX_HOURS that the index
   does not show yet means the nightly index missed it.
Exits 1 and writes the problems as Markdown when there are any.
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
INDEX_URL = "https://raw.githubusercontent.com/Gulliby-development/runeloader-index/gh-pages/index.json"
RELEASE_HOURS = 24
INDEX_HOURS = 30
BUNDLE_HOURS = 3


def vkey(v):
    return tuple(int(x) for x in re.findall(r"\d+", v or "")[:4])


def now():
    return datetime.datetime.now(datetime.timezone.utc)


def parse_time(s):
    return datetime.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)


def releases_of(repo):
    """Every release, page by page (the newest 1000 are plenty)."""
    out = []
    for page in range(1, 11):
        text = subprocess.run(["gh", "api", "repos/%s/releases?per_page=100&page=%d" % (repo, page)],
                              capture_output=True, text=True, check=True).stdout
        got = json.loads(text)
        out += got
        if len(got) < 100:
            break
    return out


def folders():
    for d in sorted(os.listdir(ROOT)):
        toc = os.path.join(ROOT, d, d + ".toc")
        if d.startswith("Gulli-") and os.path.isfile(toc):
            m = re.search(r"^## Version:\s*(\S+)", open(toc, encoding="utf-8").read(), re.M)
            group = "Core" if d == "Gulli-Toolkit" else d[len("Gulli-"):]
            yield d, group, m.group(1) if m else None, toc


def bumped_at(toc):
    """When the TOC's version line last changed on this branch."""
    out = subprocess.run(["git", "log", "-1", "--format=%ct", "-G", "^## Version:", "--", toc],
                         cwd=ROOT, capture_output=True, text=True).stdout.strip()
    return datetime.datetime.fromtimestamp(int(out), datetime.timezone.utc) if out else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default="Gulliby-development/gulli-toolkit")
    ap.add_argument("--out")
    args = ap.parse_args()

    releases = releases_of(args.repo)
    newest = {}
    bundle = None
    for r in releases:
        if r.get("draft"):
            continue
        if r["tag_name"] == "bundle":
            bundle = r
            continue
        m = re.match(r"^([A-Za-z]+)-v(\d[\w.]*)$", r["tag_name"])
        if not m or r.get("prerelease"):
            continue
        g, v = m.group(1), m.group(2)
        if g not in newest or vkey(v) > vkey(newest[g]["version"]):
            newest[g] = {"version": v, "tag": r["tag_name"], "at": parse_time(r["published_at"])}

    index = json.load(urllib.request.urlopen(INDEX_URL, timeout=60))
    generated = parse_time(index["generated"])
    in_index = {}
    for a in index.get("addons", []):
        if a["repo"].lower() == args.repo.lower():
            in_index[a.get("module") or "Core"] = a["version"]
    bundle_tags = set(re.findall(r"`([A-Za-z]+-v[\w.]+)`", (bundle or {}).get("body") or ""))
    stamps = [parse_time(x["updated_at"]) for x in (bundle or {}).get("assets", []) if x.get("updated_at")]
    bundle_at = max(stamps) if stamps else None

    problems, rows = [], []
    t = now()
    for folder, group, version, toc in folders():
        rel = newest.get(group)
        line = "| %s | %s | %s | %s | %s |" % (folder, version, rel["version"] if rel else "-",
                                               "yes" if rel and rel["tag"] in bundle_tags else "no",
                                               in_index.get(group, "-"))
        rows.append(line)
        if not rel:
            problems.append("**%s** has never been released (run Release with `%s`)." % (folder, group))
            continue
        if vkey(version) > vkey(rel["version"]):
            at = bumped_at(toc)
            if at and t - at > datetime.timedelta(hours=RELEASE_HOURS):
                problems.append("**%s** %s is on main since %s but the newest release is %s: run Release with `%s`."
                                % (folder, version, at.strftime("%Y-%m-%d %H:%M UTC"), rel["version"], group))
        elif vkey(version) < vkey(rel["version"]):
            problems.append("**%s**: main says %s, but %s is released. The TOC went back?" % (folder, version, rel["tag"]))
        if rel["tag"] not in bundle_tags and t - rel["at"] > datetime.timedelta(hours=BUNDLE_HOURS):
            problems.append("**%s**: the all-in-one zip does not have %s yet: run **All-in-one zip**." % (folder, rel["tag"]))
        idx = in_index.get(group)
        if rel["at"] < generated - datetime.timedelta(hours=2) and t - rel["at"] > datetime.timedelta(hours=INDEX_HOURS):
            if not idx:
                problems.append("**%s** is not in the index." % folder)
            elif vkey(idx) < vkey(rel["version"]):
                problems.append("**%s**: the index shows %s, the release is %s since %s."
                                % (folder, idx, rel["version"], rel["at"].strftime("%Y-%m-%d %H:%M UTC")))

    report = ["Checked %s: %d addons, %d releases, index of %s, bundle of %s." % (
        t.strftime("%Y-%m-%d %H:%M UTC"), len(rows), len(releases), index["generated"],
        bundle_at.strftime("%Y-%m-%d %H:%M UTC") if bundle_at else "-"), ""]
    if problems:
        report += ["## Problems", ""] + ["- " + p for p in problems] + [""]
    else:
        report += ["Everything on main is released, in the all-in-one zip and in the index.", ""]
    report += ["<details><summary>Every addon</summary>", "", "| Folder | main | Released | In zip | In index |",
               "|---|---|---|---|---|"] + rows + ["", "</details>"]
    text = "\n".join(report)
    print(text)
    if args.out:
        open(args.out, "w", encoding="utf-8").write(text + "\n")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
