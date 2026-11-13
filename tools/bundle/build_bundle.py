"""Build the all-in-one zip from the newest published release of the core and of every module.

    GH_TOKEN=... python3 tools/bundle/build_bundle.py owner/repo out_dir

Writes out_dir/Gulli-Toolkit-All.zip (every Gulli-* folder at the top) and out_dir/notes.md
(the versions in it). Standard library only. Exits non-zero when a release zip is missing,
does not hold its own folder, or a folder appears twice.
"""

import io
import json
import os
import re
import sys
import urllib.request
import zipfile

API = "https://api.github.com"
TAG = re.compile(r"^([A-Za-z][A-Za-z0-9]*)-v(\d.*)$")
BUNDLE_NAME = "Gulli-Toolkit-All.zip"


def get(url, token, accept="application/vnd.github+json"):
    req = urllib.request.Request(url, headers={"Accept": accept, "User-Agent": "gulli-toolkit-bundle"})
    # The token goes only to the API host; asset downloads redirect to signed URLs.
    if token and url.startswith(API):
        req.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def newest_per_group(releases):
    """{group: release}: the newest published, non-draft, non-prerelease release of each tag group."""
    out = {}
    for r in sorted(releases, key=lambda r: r.get("published_at") or "", reverse=True):
        if r.get("draft") or r.get("prerelease"):
            continue
        m = TAG.match(r.get("tag_name") or "")
        if m and m.group(1) not in out:
            out[m.group(1)] = r
    return out


def folder_of(group):
    return "Gulli-Toolkit" if group == "Core" else "Gulli-" + group


def asset_url(release, token, name):
    for a in release.get("assets") or []:
        if a.get("name") == name:
            return a["url"]
    return None


def zip_of(release, token):
    """Bytes of the release's Forever zip, named by its release.json."""
    rj = asset_url(release, token, "release.json")
    if not rj:
        raise SystemExit("%s has no release.json" % release["tag_name"])
    data = json.loads(get(rj, token, "application/octet-stream"))
    name = ((data.get("releases") or [{}])[0]).get("filename")
    url = name and asset_url(release, token, name)
    if not url:
        raise SystemExit("%s: release.json names %r, which is not an asset" % (release["tag_name"], name))
    return name, get(url, token, "application/octet-stream")


def main(repo, out_dir):
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    releases, page = [], 1
    while True:
        batch = json.loads(get("%s/repos/%s/releases?per_page=100&page=%d" % (API, repo, page), token))
        releases += batch
        if len(batch) < 100:
            break
        page += 1
    groups = newest_per_group(releases)
    if "Core" not in groups:
        raise SystemExit("no Core-v release yet")

    os.makedirs(out_dir, exist_ok=True)
    seen, lines = set(), []
    with zipfile.ZipFile(os.path.join(out_dir, BUNDLE_NAME), "w", zipfile.ZIP_DEFLATED) as bundle:
        for group in sorted(groups, key=lambda g: (g != "Core", g.lower())):
            rel = groups[group]
            name, raw = zip_of(rel, token)
            want = folder_of(group)
            with zipfile.ZipFile(io.BytesIO(raw)) as z:
                tops = {n.split("/", 1)[0] for n in z.namelist() if n.strip("/")}
                if want not in tops:
                    raise SystemExit("%s does not hold the folder %s" % (name, want))
                for top in tops:
                    if top in seen:
                        raise SystemExit("%s is in two releases" % top)
                    seen.add(top)
                for info in z.infolist():
                    if info.is_dir():
                        continue
                    parts = info.filename.split("/")
                    if ".." in parts or info.filename.startswith("/"):
                        raise SystemExit("%s has an unsafe path %s" % (name, info.filename))
                    bundle.writestr(info, z.read(info))
            lines.append("- %s %s (`%s`)" % (want, TAG.match(rel["tag_name"]).group(2), rel["tag_name"]))
    with open(os.path.join(out_dir, "notes.md"), "w") as f:
        f.write("Every Gulli addon in one zip, built from the newest release of each one. "
                "Unpack it into `Interface/AddOns`.\n\n" + "\n".join(lines) + "\n")
    print("\n".join(lines))
    print("%d addons" % len(lines))
    # Every module folder of the checkout belongs in the bundle; one without a release yet is
    # reported, not fatal, since its first release may still be running.
    missing = sorted(d for d in os.listdir(".") if d.startswith("Gulli-") and os.path.isdir(d) and d not in seen)
    for d in missing:
        print("::warning::%s has no published release, so it is not in %s. Run Release for it." % (d, BUNDLE_NAME))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
