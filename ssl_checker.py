#!/usr/bin/env python3
# ssl_checker.py
# Simple cert expiry checker used by Jenkins pipeline.
# Fetches cert enddate via openssl, parses it as UTC-aware datetime, and prints days left.

from datetime import datetime, timezone
import subprocess
import sys

HOST = "ssl-automation.duckdns.org"
PORT = 443

def get_cert_enddate(host: str, port: int) -> datetime:
    """
    Use openssl to get the cert enddate and return a timezone-aware datetime in UTC.
    """
    cmd = f"openssl s_client -connect {host}:{port} -servername {host} </dev/null 2>/dev/null | openssl x509 -noout -enddate"
    try:
        out = subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL).decode().strip()
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"Failed to fetch certificate info for {host}:{port}: {e}") from e

    # expected: notAfter=Jan 29 14:28:52 2026 GMT
    if not out.startswith("notAfter="):
        raise RuntimeError(f"Unexpected openssl output: {out}")
    date_str = out.split("=", 1)[1].strip()

    # parse like: Jan 29 14:28:52 2026 GMT
    # strptime format: %b %d %H:%M:%S %Y GMT
    try:
        expiry_naive = datetime.strptime(date_str, "%b %d %H:%M:%S %Y GMT")
    except ValueError:
        # try alternative format (some locales): `%b %e %H:%M:%S %Y GMT` isn't supported in strptime on all platforms,
        # but the above should work for typical openssl output.
        raise

    # make it timezone-aware (UTC)
    expiry_aware = expiry_naive.replace(tzinfo=timezone.utc)
    return expiry_aware

def check_ssl_expiry(host: str, port: int):
    try:
        expiry = get_cert_enddate(host, port)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(2)

    now = datetime.now(timezone.utc)
    delta = expiry - now
    days_left = delta.days

    print(f"SSL Certificate for {host} expires on {expiry.isoformat()}")
    print(f"Days left: {days_left}")

    # exit codes for pipeline decisions (optional)
    # 0 -> ok, 1 -> near expiry, 2 -> error
    if days_left <= 30:
        # near expiry; return non-zero if you want pipeline to treat as failure
        sys.exit(1)
    sys.exit(0)

if __name__ == "__main__":
    check_ssl_expiry(HOST, PORT)

