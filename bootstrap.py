"""First-boot setup for JT Doc Tools on Railway.

Upstream ships with login switched off: every tool, the admin pages and the
API are open, and /setup-admin lets the first visitor create the admin.
Before the web port opens, this script:

* creates the admin user ADMIN_USERNAME with ADMIN_PASSWORD and switches the
  local login backend on (same code path as upstream's setup page);
* switches login back on if it was turned off but users exist;
* keeps the admin's password equal to ADMIN_PASSWORD (change the variable
  and redeploy to change or recover it);
* on first boot, writes job-concurrency defaults sized from the memory limit.

Any failure exits non-zero so the service never starts without a login.
"""
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, "/app")

from app.core import (audit_db, auth_db, auth_settings, db, passwords,  # noqa: E402
                      permissions, roles)

username = os.environ["ADMIN_USERNAME"].strip()
password = os.environ["ADMIN_PASSWORD"]
data_dir = Path(os.environ.get("JTDT_DATA_DIR", "/data"))
mem_mb = int(os.environ.get("JTDT_MEM_MB", "0") or 0)


def log(msg):
    print(f"jtdt-bootstrap: {msg}", flush=True)


def write_concurrency_defaults():
    path = data_dir / "concurrency.json"
    if path.exists():
        return
    if mem_mb and mem_mb < 1600:
        cfg = {"max_concurrent_jobs": 1, "max_office_concurrent": 1,
               "max_remote_concurrent": 1, "soffice_cpu_percent": 0,
               "reserve_mb": 128}
    elif mem_mb and mem_mb < 3200:
        cfg = {"max_concurrent_jobs": 2, "max_office_concurrent": 1,
               "max_remote_concurrent": 1, "soffice_cpu_percent": 0,
               "reserve_mb": 256}
    else:
        return  # upstream defaults are fine on 4 GB and more
    path.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
    log(f"wrote {path.name} for a {mem_mb} MB limit: {cfg}")


def main():
    ok, err = passwords.validate_password(password)
    if not ok:
        sys.exit(f"jtdt-bootstrap: ADMIN_PASSWORD rejected: {err}")

    auth_db.init()
    audit_db.init()
    roles.seed_builtin_roles()
    conn = auth_db.conn()
    n_users = conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
    backend = auth_settings.get_backend()

    if backend == "off":
        if n_users == 0:
            auth_settings.enable_local_with_admin(
                admin_username=username, admin_display_name=username,
                admin_password=password, admin_password_confirm=password,
                actor_ip="railway-bootstrap")
            log(f"created admin '{username}' and switched login on")
        else:
            auth_settings.reenable_local_with_existing(actor_ip="railway-bootstrap")
            log("login was off but users exist: switched local login back on")

    row = conn.execute(
        "SELECT id, password_hash FROM users WHERE username=? AND source='local'",
        (username,)).fetchone()
    if row is None:
        # ADMIN_USERNAME was changed after the first deploy: add it as an admin.
        import time
        with db.tx(conn):
            cur = conn.execute(
                "INSERT INTO users(username, display_name, password_hash, source, "
                " enabled, is_admin_seed, created_at) VALUES (?, ?, ?, 'local', 1, 0, ?)",
                (username, username, passwords.hash_password(password), time.time()))
            uid = cur.lastrowid
        permissions.set_subject_roles("user", str(uid), ["admin"])
        log(f"added admin '{username}'")
    elif not passwords.verify_password(password, row["password_hash"]):
        with db.tx(conn):
            conn.execute("UPDATE users SET password_hash=?, enabled=1 WHERE id=?",
                         (passwords.hash_password(password), row["id"]))
            conn.execute("DELETE FROM sessions WHERE user_id=?", (row["id"],))
            conn.execute("DELETE FROM lockouts WHERE key=?", (f"user:{username.lower()}",))
        log(f"set the password of '{username}' from ADMIN_PASSWORD")

    # Final check: login must be on and the admin must be able to sign in.
    if auth_settings.get_backend() == "off":
        sys.exit("jtdt-bootstrap: login is still off; refusing to start")
    row = conn.execute(
        "SELECT password_hash, enabled FROM users WHERE username=? AND source='local'",
        (username,)).fetchone()
    if not row or not row["enabled"] or not passwords.verify_password(password, row["password_hash"]):
        sys.exit("jtdt-bootstrap: admin account check failed; refusing to start")

    write_concurrency_defaults()
    log("ok")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001
        sys.exit(f"jtdt-bootstrap: failed: {e!r}")
