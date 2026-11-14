#!/usr/bin/env python3
"""Baixa arquivos do iPad via canal SSH (robusto com nomes especiais)."""
import os
import sys

import paramiko

HOST = "127.0.0.1"
PORT = 2222
USER = "root"
PASSWORD = "alpine"

paramiko.Transport._preferred_kex = (
    "diffie-hellman-group14-sha1",
    "diffie-hellman-group1-sha1",
    "diffie-hellman-group-exchange-sha1",
)
paramiko.Transport._preferred_keys = ("ssh-rsa", "ssh-dss")


def connect(retries=3, delay=4):
    last = None
    for _ in range(retries):
        c = paramiko.SSHClient()
        c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        try:
            c.connect(HOST, PORT, username=USER, password=PASSWORD,
                      allow_agent=False, look_for_keys=False,
                      timeout=20, banner_timeout=40, auth_timeout=40)
            return c
        except Exception as e:  # noqa: BLE001
            last = e
            import time
            time.sleep(delay)
    raise last


def main():
    remote, local = sys.argv[1], sys.argv[2]
    c = connect()
    try:
        cmd = "cat '%s'" % remote.replace("'", "'\\''")
        _, o, e = c.exec_command(cmd)
        data = o.read()
        err = e.read().decode("utf-8", "replace")
        if err.strip():
            print("STDERR:", err.strip())
        with open(local, "wb") as f:
            f.write(data)
        print("OK %s -> %s (%d bytes)" % (remote, local, len(data)))
    finally:
        c.close()


if __name__ == "__main__":
    main()
