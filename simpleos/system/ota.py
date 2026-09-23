#!/usr/bin/env python3
"""GitHub Releases check / download for SimpleOS OTA."""
import json
import os
import ssl
import sys
import urllib.error
import urllib.request

API = "https://api.github.com/repos/boorngos/SimpleOS/releases/latest"
UA = "SimpleOS-OTA/1.0 (RG DS)"
STATUS = "/tmp/simpleos-ota"


def write_status(**kv):
    lines = []
    for k, v in kv.items():
        if v is None:
            continue
        lines.append("%s=%s" % (k, str(v).replace("\n", " ").replace("\r", "")))
    tmp = STATUS + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    os.replace(tmp, STATUS)


def version_key(s):
    digits = "".join(c for c in (s or "") if c.isdigit())
    if len(digits) >= 8:
        return int(digits[:8])
    if digits:
        return int(digits)
    return 0


def fetch(url, dest=None, timeout=30, progress=None):
    req = urllib.request.Request(url)
    req.add_header("User-Agent", UA)
    req.add_header("Accept", "application/vnd.github+json")

    def open_url(ctx=None):
        kwargs = {"timeout": timeout}
        if ctx is not None:
            kwargs["context"] = ctx
        return urllib.request.urlopen(req, **kwargs)

    resp = None
    try:
        resp = open_url()
    except Exception:
        try:
            resp = open_url(ssl._create_unverified_context())
        except Exception:
            return None
    try:
        if dest:
            total = 0
            try:
                total = int(resp.headers.get("Content-Length") or 0)
            except Exception:
                total = 0
            got = 0
            with open(dest, "wb") as f:
                while True:
                    chunk = resp.read(64 * 1024)
                    if not chunk:
                        break
                    f.write(chunk)
                    got += len(chunk)
                    if progress:
                        progress(got, total)
            return b""
        return resp.read()
    finally:
        try:
            resp.close()
        except Exception:
            pass


def pick_asset(rel):
    assets = rel.get("assets") or []
    best = None
    for a in assets:
        name = a.get("name") or ""
        url = a.get("browser_download_url") or ""
        if not url:
            continue
        low = name.lower()
        if low.endswith(".zip") and "simpleos" in low:
            return name, url
        if low.endswith(".zip") and best is None:
            best = (name, url)
    if best:
        return best
    tag = (rel.get("tag_name") or "").lstrip("vV")
    if tag:
        guess = "https://github.com/boorngos/SimpleOS/releases/download/%s/SimpleOS-RGDS-%s.zip" % (
            rel.get("tag_name") or tag,
            tag,
        )
        return "SimpleOS-RGDS-%s.zip" % tag, guess
    return "", ""


def do_check(local):
    write_status(phase="check", pct=5, local=local, note="Checking for updates")
    body = fetch(API, timeout=25)
    if body is None:
        write_status(phase="fail", pct=0, local=local, note="No network")
        return 1
    try:
        rel = json.loads(body.decode("utf-8", "replace"))
    except Exception:
        write_status(phase="fail", pct=0, local=local, note="Bad reply")
        return 1
    if not isinstance(rel, dict) or rel.get("message") == "Not Found":
        write_status(phase="none", pct=0, local=local, remote=local, note="No releases")
        return 0
    tag = (rel.get("tag_name") or rel.get("name") or "").strip()
    name, url = pick_asset(rel)
    remote = "".join(c for c in (name or tag) if c.isdigit())[:8]
    if not remote:
        remote = tag.lstrip("vV")
    if not url:
        write_status(phase="none", pct=0, local=local, remote=remote or local, note="Up to date")
        return 0
    force = os.environ.get("SIMPLEOS_OTA_FORCE", "") == "1"
    if version_key(remote) <= version_key(local) and not force:
        write_status(
            phase="none",
            pct=0,
            local=local,
            remote=remote or local,
            note="Up to date",
        )
        return 0
    write_status(
        phase="ask",
        pct=0,
        local=local,
        remote=remote,
        url=url,
        note="Update available",
    )
    return 0


def do_apply(url, dest, local, remote):
    if not url or not dest:
        write_status(phase="fail", pct=0, local=local, note="Missing package")
        return 1
    os.makedirs(os.path.dirname(dest), exist_ok=True)

    def progress(got, total):
        if total > 0:
            pct = 8 + int(62 * got / total)
            if pct > 70:
                pct = 70
        else:
            pct = 20
        write_status(
            phase="apply",
            pct=pct,
            local=local,
            remote=remote,
            url=url,
            note="Downloading",
        )

    write_status(phase="apply", pct=5, local=local, remote=remote, url=url, note="Downloading")
    if fetch(url, dest=dest, timeout=180, progress=progress) is None:
        write_status(phase="fail", pct=0, local=local, remote=remote, note="Download failed")
        return 1
    if not os.path.isfile(dest) or os.path.getsize(dest) < 64:
        write_status(phase="fail", pct=0, local=local, remote=remote, note="Empty package")
        return 1
    write_status(phase="apply", pct=72, local=local, remote=remote, url=url, note="Downloaded")
    return 0


def main():
    if len(sys.argv) < 3:
        return 1
    cmd = sys.argv[1]
    local = sys.argv[2]
    if cmd == "check":
        return do_check(local)
    if cmd == "apply":
        url = sys.argv[3] if len(sys.argv) > 3 else os.environ.get("SIMPLEOS_OTA_URL", "")
        dest = sys.argv[4] if len(sys.argv) > 4 else os.environ.get("SIMPLEOS_OTA_ZIP", "")
        remote = sys.argv[5] if len(sys.argv) > 5 else ""
        return do_apply(url, dest, local, remote)
    return 1


if __name__ == "__main__":
    sys.exit(main())
