"""Upload Gulli releases to CurseForge.

    CF_API_TOKEN=... GH_TOKEN=... python3 tools/curseforge/upload.py owner/repo <tag | all>

The projects are in tools/curseforge/projects.json. A module in "separate" has its own
CurseForge project and gets its own release zip. Every other folder (the core and the small
modules) ships in the "toolkit" project as one zip, rebuilt from the newest release of each, so
a release of any of them uploads a new Gulli Toolkit file. "all" uploads every project once (the
first upload). Without a token, or for a project without an id, it says so and does nothing.
Standard library only.
"""

import io
import json
import os
import sys
import urllib.request
import uuid
import zipfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bundle"))
import build_bundle as B  # noqa: E402

CF = "https://wow.curseforge.com"
CONFIG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "projects.json")


def targets(tag, config):
    """What a release uploads: ["toolkit"] or [<separate module>]; "all" gives every project."""
    sep = config["separate"]
    if tag == "all":
        return ["toolkit"] + sorted(sep)
    m = B.TAG.match(tag or "")
    if not m:
        raise SystemExit("%r is not a release tag" % tag)
    return [m.group(1)] if m.group(1) in sep else ["toolkit"]


def project_of(target, config):
    return config["toolkit"] if target == "toolkit" else config["separate"][target]


def pick_version(versions, name, fixed=None):
    """The game version id for the Forever build: the fixed id, else the one version so named."""
    if fixed:
        return int(fixed)
    hits = [v for v in versions if v.get("name") == name]
    if len(hits) != 1:
        near = sorted({"%s (id %s, type %s)" % (v.get("name"), v.get("id"), v.get("gameVersionTypeID"))
                       for v in versions if str(v.get("name", "")).startswith(name.rsplit(".", 1)[0])})
        raise SystemExit("%d game versions are named %s; set game_version_id in projects.json. Near: %s"
                         % (len(hits), name, ", ".join(near) or "none"))
    return hits[0]["id"]


def metadata(display, changelog, version_id, toolkit_slug=None):
    meta = {"changelog": changelog, "changelogType": "markdown", "displayName": display,
            "gameVersions": [version_id], "releaseType": "release"}
    if toolkit_slug:
        meta["relations"] = {"projects": [{"slug": toolkit_slug, "type": "optionalDependency"}]}
    return meta


def multipart(fields, file_name, file_bytes):
    boundary = uuid.uuid4().hex
    out = io.BytesIO()
    for k, v in fields.items():
        out.write(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % (boundary, k, v)).encode())
    out.write(("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\n"
               "Content-Type: application/zip\r\n\r\n" % (boundary, file_name)).encode())
    out.write(file_bytes)
    out.write(("\r\n--%s--\r\n" % boundary).encode())
    return out.getvalue(), "multipart/form-data; boundary=" + boundary


def cf(path, token, data=None, ctype=None):
    req = urllib.request.Request(CF + path, data=data, headers={"X-Api-Token": token, "User-Agent": "gulli-toolkit"})
    if ctype:
        req.add_header("Content-Type", ctype)
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read())


def toolkit_zip(groups, separate, token):
    """One zip of the core and every module without its own project, and the lines of versions."""
    buf, lines = io.BytesIO(), []
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as out:
        for group in sorted(groups, key=lambda g: (g != "Core", g.lower())):
            if group in separate:
                continue
            rel = groups[group]
            name, raw = B.zip_of(rel, token)
            with zipfile.ZipFile(io.BytesIO(raw)) as z:
                for info in z.infolist():
                    top = info.filename.split("/", 1)[0]
                    if ".." in info.filename.split("/") or info.filename.startswith("/"):
                        raise SystemExit("%s has an unsafe path %s" % (name, info.filename))
                    if top in separate_folders(separate):
                        raise SystemExit("%s holds %s, which has its own project" % (name, top))
                    if not info.is_dir():
                        out.writestr(info, z.read(info))
            lines.append("- %s %s" % (B.folder_of(group), B.TAG.match(rel["tag_name"]).group(2)))
    return buf.getvalue(), lines


def separate_folders(separate):
    return {B.folder_of(g) for g in separate}


def main(repo, tag):
    with open(CONFIG) as f:
        config = json.load(f)
    cf_token = os.environ.get("CF_API_TOKEN")
    gh_token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    want = [t for t in targets(tag, config) if project_of(t, config).get("id")]
    for t in targets(tag, config):
        if t not in want:
            print("::notice::%s has no CurseForge project id in projects.json yet; nothing uploaded." % t)
    if not want:
        return
    if not cf_token:
        print("::notice::No CF_API_TOKEN secret; nothing uploaded to CurseForge.")
        return
    version_id = pick_version(cf("/api/game/versions", cf_token), config["game_version"], config.get("game_version_id"))
    releases, page = [], 1
    while True:
        batch = json.loads(B.get("%s/repos/%s/releases?per_page=100&page=%d" % (B.API, repo, page), gh_token))
        releases += batch
        if len(batch) < 100:
            break
        page += 1
    groups = B.newest_per_group(releases)
    by_tag = {r.get("tag_name"): r for r in releases}
    note = (by_tag.get(tag) or {}).get("body") or ""
    for t in want:
        pid = project_of(t, config)["id"]
        if t == "toolkit":
            if "Core" not in groups:
                raise SystemExit("no Core-v release yet")
            data, lines = toolkit_zip(groups, config["separate"], gh_token)
            core = B.TAG.match(groups["Core"]["tag_name"]).group(2)
            m = B.TAG.match(tag) if tag != "all" else None
            display = "Gulli Toolkit %s" % core
            if m and m.group(1) != "Core":
                display += " (%s %s)" % (m.group(1), m.group(2))
            file_name = "Gulli-Toolkit-%s.zip" % display.split(" ", 2)[2].replace(" ", "-").replace("(", "").replace(")", "")
            changelog = (("## %s\n\n%s\n\n" % (tag, note)) if note else "") + "## In this zip\n\n" + "\n".join(lines) + "\n"
            meta = metadata(display, changelog, version_id)
        else:
            rel = groups.get(t)
            if not rel:
                print("::warning::%s has no published release yet." % t)
                continue
            file_name, data = B.zip_of(rel, gh_token)
            ver = B.TAG.match(rel["tag_name"]).group(2)
            body = rel.get("body") or "Gulli-%s %s" % (t, ver)
            meta = metadata("Gulli-%s %s" % (t, ver), body, version_id, config["toolkit"].get("slug"))
        payload, ctype = multipart({"metadata": json.dumps(meta)}, file_name, data)
        res = cf("/api/projects/%s/upload-file" % pid, cf_token, payload, ctype)
        print("Uploaded %s to project %s as file %s (%s)" % (file_name, pid, res.get("id"), meta["displayName"]))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
