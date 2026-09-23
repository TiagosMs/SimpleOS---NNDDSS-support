#!/usr/bin/env python3
import os
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HOST = "https://retroachievements.org/dorequest.php"
UA = "SimpleOS/1.0.0 (RGDS)"


def post_bytes(data):
    req = urllib.request.Request(HOST, data=data)
    req.add_header("User-Agent", UA)
    req.add_header("Content-Type", "application/x-www-form-urlencoded")

    def fetch(ctx=None):
        try:
            kwargs = {"timeout": 20}
            if ctx is not None:
                kwargs["context"] = ctx
            with urllib.request.urlopen(req, **kwargs) as resp:
                return resp.read()
        except urllib.error.HTTPError as e:
            body = e.read()
            return body if body else None
        except Exception:
            return None

    out = fetch()
    if out is None:
        out = fetch(ssl._create_unverified_context())
    return out or b""


def post_file(url, post_path, dest=None):
    data = open(post_path, "rb").read()
    req = urllib.request.Request(url, data=data)
    req.add_header("User-Agent", UA)
    req.add_header("Content-Type", "application/x-www-form-urlencoded")

    def fetch(ctx=None):
        try:
            kwargs = {"timeout": 20}
            if ctx is not None:
                kwargs["context"] = ctx
            with urllib.request.urlopen(req, **kwargs) as resp:
                return resp.read()
        except urllib.error.HTTPError as e:
            body = e.read()
            return body if body else None
        except Exception:
            return None

    out = fetch()
    if out is None:
        out = fetch(ssl._create_unverified_context())
    if out is None:
        return False
    if dest:
        open(dest, "wb").write(out)
        return True
    sys.stdout.buffer.write(out)
    return True


def read_kv(path):
    d = {}
    try:
        for line in open(path, "r", encoding="utf-8", errors="replace"):
            if "=" in line:
                k, v = line.split("=", 1)
                d[k.strip()] = v.strip()
    except Exception:
        pass
    return d


def write_unlocks(root, body):
    text = body.decode("utf-8", "replace")
    ids = []
    for key in ("Unlocks",):
        i = text.find('"%s"' % key)
        if i < 0:
            continue
        b = text.find("[", i)
        e = text.find("]", b)
        if b < 0 or e < 0:
            continue
        chunk = text[b + 1 : e]
        for part in chunk.split(","):
            part = part.strip()
            if part.isdigit():
                ids.append(part)
    path = os.path.join(root, "userdata", "ra-unlocks")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8").write("\n".join(ids) + ("\n" if ids else ""))


def handle(root, sess, line, last_ping):
    user = sess.get("user") or ""
    token = sess.get("token") or ""
    hid = sess.get("id") or ""
    hh = sess.get("hash") or ""
    if not user or not token:
        return last_ping
    u = urllib.parse.quote(user, safe="")
    t = urllib.parse.quote(token, safe="")

    def log(msg):
        try:
            open("/tmp/simpleos.log", "a", encoding="utf-8").write("simpleos: ra " + msg + "\n")
        except Exception:
            pass

    if line == "session" and hid and hh:
        body = post_bytes(
            ("r=startsession&u=%s&t=%s&g=%s&m=%s&h=0" % (u, t, hid, hh)).encode()
        )
        if body:
            write_unlocks(root, body)
            log("session softcore %s bytes=%d" % (hid, len(body)))
        else:
            log("session fail")
        return time.time()
    if line.startswith("award ") and hh:
        aid = line[6:].strip()
        if aid.isdigit():
            body = post_bytes(
                ("r=awardachievement&u=%s&t=%s&a=%s&h=0&m=%s" % (u, t, aid, hh)).encode()
            )
            snippet = (body or b"")[:120].decode("utf-8", "replace").replace("\n", " ")
            log("award softcore %s bytes=%d %s" % (aid, len(body or b""), snippet))
        return last_ping
    if line == "ping" and hid:
        post_bytes(("r=ping&u=%s&t=%s&g=%s&m=%s&h=0" % (u, t, hid, hh)).encode())
        return time.time()
    return last_ping


def worker(root):
    qpath = os.path.join(root, "userdata", "ra-queue")
    spath = os.path.join(root, "userdata", "ra-session")
    last_ping = 0.0
    booted = False
    while True:
        sess = read_kv(spath)
        if not booted and sess.get("on") == "1":
            last_ping = handle(root, sess, "session", last_ping)
            booted = True
        work = qpath + ".work"
        if os.path.isfile(qpath):
            try:
                os.rename(qpath, work)
            except Exception:
                work = ""
            if work and os.path.isfile(work):
                try:
                    lines = open(work, "r", encoding="utf-8", errors="replace").read().splitlines()
                except Exception:
                    lines = []
                try:
                    os.remove(work)
                except Exception:
                    pass
                for line in lines:
                    line = line.strip()
                    if line:
                        last_ping = handle(root, sess, line, last_ping)
        now = time.time()
        if sess.get("on") == "1" and now - last_ping >= 120:
            last_ping = handle(root, sess, "ping", last_ping)
        time.sleep(0.35)


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "worker":
        worker(sys.argv[2])
        sys.exit(0)
    if len(sys.argv) < 3:
        sys.exit(1)
    url, post = sys.argv[1], sys.argv[2]
    dest = sys.argv[3] if len(sys.argv) > 3 else None
    sys.exit(0 if post_file(url, post, dest) else 1)
