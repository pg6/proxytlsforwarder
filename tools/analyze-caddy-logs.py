#!/usr/bin/env python3
"""Caddy TLS certificate log analyzer.

Usage:
    ./analyze-caddy-logs.py                        # CLI mode: fetch logs from docker compose
    ./analyze-caddy-logs.py --cron                  # Cron mode: only issues, exit 1 if problems found
    ./analyze-caddy-logs.py --file <logfile>        # CLI mode: read from a file
    ./analyze-caddy-logs.py --cron --file <logfile> # Cron mode: read from a file
"""

import json
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timezone


def get_log_lines(filepath=None):
    """Get log lines from a file or docker compose."""
    if filepath:
        with open(filepath) as f:
            yield from f
    else:
        result = subprocess.run(
            ["docker", "compose", "logs", "--no-color", "caddy"],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            print(f"Error fetching docker compose logs: {result.stderr.strip()}", file=sys.stderr)
            sys.exit(2)
        yield from result.stdout.splitlines()


def parse_non_access_lines(lines):
    """Parse log lines, skip access log lines, yield parsed JSON dicts."""
    for line in lines:
        line = line.strip()
        # Strip docker compose prefix ("redirect-server  | ")
        if line.startswith("redirect-server"):
            _, _, line = line.partition("| ")
            line = line.strip()
        if not line or '"http.log.access"' in line:
            continue
        try:
            yield json.loads(line)
        except json.JSONDecodeError:
            continue


def ts_to_dt(ts):
    return datetime.fromtimestamp(ts, tz=timezone.utc)


def ts_to_str(ts):
    return ts_to_dt(ts).strftime("%Y-%m-%d %H:%M:%S UTC")


def analyze(filepath=None):
    # Cert lifecycle tracking
    certs_obtained = {}        # identifier -> last success timestamp
    certs_failed = defaultdict(list)  # identifier -> [(ts, error)]
    certs_retrying = defaultdict(int)  # identifier -> retry count
    certs_renewed = {}         # identifier -> last renewal ts
    cert_expiries = {}         # identifier -> expiry ts

    # Challenge failures
    challenge_failures = defaultdict(list)  # identifier -> [(ts, error)]

    # General issues
    errors = []    # (ts, logger, msg, details)
    warnings = []  # (ts, logger, msg, details)

    # Startup info
    managed_domains = []
    startup_ts = None

    # DNS / network errors
    dns_errors = []

    for entry in parse_non_access_lines(get_log_lines(filepath)):
        level = entry.get("level", "")
        logger = entry.get("logger", "")
        msg = entry.get("msg", "")
        ts = entry.get("ts", 0)
        identifier = entry.get("identifier", "")
        error = entry.get("error", "")

        # Track startup
        if msg == "serving initial configuration" and startup_ts is None:
            startup_ts = ts

        # Managed domains list
        if msg == "enabling automatic TLS certificate management":
            managed_domains = entry.get("domains", [])

        # Certificate obtained successfully
        if msg == "certificate obtained successfully":
            certs_obtained[identifier] = ts

        # Certificate renewal info
        if msg == "updated and stored ACME renewal information":
            identifiers = entry.get("identifiers", [])
            expiry = entry.get("cert_expiry", 0)
            for ident in identifiers:
                certs_renewed[ident] = ts
                if expiry:
                    cert_expiries[ident] = expiry

        # Cert obtain failures
        if msg == "could not get certificate from issuer":
            certs_failed[identifier].append((ts, error))

        # Retries
        if msg == "will retry":
            if error.startswith("["):
                ident = error.split("]")[0][1:]
                certs_retrying[ident] += 1

        # Challenge failures (both warn and error)
        if "challenge" in msg.lower() and error:
            server_name = entry.get("server_name", "") or entry.get("host", "")
            if server_name:
                challenge_failures[server_name].append((ts, error))

        # Job failures
        if msg == "job failed":
            errors.append((ts, logger, msg, error))

        # DNS resolution errors
        if "dial tcp: lookup" in error or "server misbehaving" in error:
            dns_errors.append((ts, msg, error))

        # Collect all errors and warnings (deduplicated later)
        if level == "error":
            errors.append((ts, logger, msg, error or str(entry)))
        elif level == "warn" and "tls" in logger:
            warnings.append((ts, logger, msg, error or str(entry)))

    return {
        "startup_ts": startup_ts,
        "managed_domains": managed_domains,
        "certs_obtained": certs_obtained,
        "certs_failed": certs_failed,
        "certs_retrying": certs_retrying,
        "certs_renewed": certs_renewed,
        "cert_expiries": cert_expiries,
        "challenge_failures": challenge_failures,
        "errors": errors,
        "warnings": warnings,
        "dns_errors": dns_errors,
    }


def get_unresolved_failures(data):
    """Return cert failures where no successful obtain happened after the last failure."""
    unresolved = {}
    for ident, failures in data["certs_failed"].items():
        last_failure_ts = failures[-1][0]
        last_success_ts = data["certs_obtained"].get(ident, 0)
        if last_failure_ts > last_success_ts:
            unresolved[ident] = failures
    return unresolved


def print_issues(data):
    """Print only actionable issues. Returns True if any issues found."""
    has_issues = False
    now = datetime.now(timezone.utc).timestamp()

    # Unresolved cert failures (failed and never succeeded after)
    unresolved = get_unresolved_failures(data)
    if unresolved:
        has_issues = True
        print("UNRESOLVED CERT FAILURES (never obtained after last failure):")
        for ident, failures in sorted(unresolved.items()):
            last_ts, last_err = failures[-1]
            print(f"  {ident}")
            print(f"    Last failure: {ts_to_str(last_ts)}")
            print(f"    Error: {last_err[:200]}")
            print(f"    Total failures: {len(failures)}")
        print()

    # Certs expiring within 7 days
    expiring_soon = {
        ident: exp
        for ident, exp in data["cert_expiries"].items()
        if exp - now < 7 * 86400
    }
    if expiring_soon:
        has_issues = True
        print("CERTS EXPIRING WITHIN 7 DAYS:")
        for ident, exp in sorted(expiring_soon.items(), key=lambda x: x[1]):
            days_left = (exp - now) / 86400
            status = "EXPIRED" if days_left < 0 else f"{days_left:.1f} days left"
            print(f"  {ident} — expires {ts_to_str(exp)} ({status})")
        print()

    # Managed domains with no cert tracked at all
    tracked = set(data["cert_expiries"].keys()) | set(data["certs_obtained"].keys())
    untracked = [d for d in data["managed_domains"] if d not in tracked]
    if untracked:
        has_issues = True
        print("MANAGED DOMAINS WITH NO CERT TRACKED:")
        for d in sorted(untracked):
            print(f"  {d}")
        print()

    # Job failures — only report if the cert was never obtained after
    job_failures = []
    for ts, logger, msg, err in data["errors"]:
        if msg != "job failed":
            continue
        # Extract identifier from "identifier: obtaining certificate: ..."
        ident = err.split(":")[0].strip()
        last_obtained = data["certs_obtained"].get(ident, 0)
        if ts > last_obtained:
            job_failures.append((ts, ident, err))
    if job_failures:
        has_issues = True
        print("UNRESOLVED JOB FAILURES:")
        seen = set()
        for ts, ident, err in job_failures:
            if ident not in seen:
                seen.add(ident)
                print(f"  {ts_to_str(ts)}: {err[:200]}")
        print()

    # DNS errors (deduplicated, only last 24h)
    recent_dns = [(ts, msg, err) for ts, msg, err in data["dns_errors"] if now - ts < 86400]
    if recent_dns:
        has_issues = True
        print("DNS/NETWORK ERRORS (last 24h):")
        seen = set()
        for ts, msg, err in recent_dns:
            short = err[:100]
            if short not in seen:
                seen.add(short)
                print(f"  {ts_to_str(ts)}: {err[:200]}")
        print()

    return has_issues


def print_full_stats(data):
    """Print comprehensive stats for CLI mode."""
    now = datetime.now(timezone.utc).timestamp()

    print("=" * 70)
    print("CADDY TLS CERTIFICATE LOG ANALYSIS")
    print("=" * 70)
    print()

    # Overview
    if data["startup_ts"]:
        uptime_days = (now - data["startup_ts"]) / 86400
        print(f"Server started:    {ts_to_str(data['startup_ts'])} ({uptime_days:.1f} days ago)")
    print(f"Managed domains:   {len(data['managed_domains'])}")
    print(f"Certs tracked:     {len(data['cert_expiries'])}")
    print(f"Certs obtained:    {len(data['certs_obtained'])}")
    print(f"Total errors:      {len(data['errors'])}")
    print(f"Total TLS warns:   {len(data['warnings'])}")
    print()

    # Cert status overview sorted by expiry
    print("-" * 70)
    print("CERTIFICATE STATUS (by expiry)")
    print("-" * 70)

    if data["cert_expiries"]:
        for ident, exp in sorted(data["cert_expiries"].items(), key=lambda x: x[1]):
            days_left = (exp - now) / 86400
            if days_left < 0:
                status = "EXPIRED"
            elif days_left < 7:
                status = "EXPIRING SOON"
            elif days_left < 30:
                status = "OK"
            else:
                status = "OK"
            renewed = data["certs_renewed"].get(ident)
            renewed_str = f"  renewed {ts_to_str(renewed)}" if renewed else ""
            print(f"  [{status:>13}] {ident}")
            print(f"                 expires {ts_to_str(exp)} ({days_left:.0f}d){renewed_str}")
    else:
        print("  No certificate expiry data found in logs.")
    print()

    # Cert obtain history (condensed - group by date)
    if data["certs_obtained"]:
        print("-" * 70)
        print("CERT OBTAIN HISTORY")
        print("-" * 70)
        by_date = defaultdict(list)
        for ident, ts in data["certs_obtained"].items():
            date = ts_to_dt(ts).strftime("%Y-%m-%d")
            by_date[date].append(ident)
        for date in sorted(by_date):
            idents = sorted(by_date[date])
            print(f"  {date}: {len(idents)} certs")
            for ident in idents:
                print(f"    {ident}")
        print()

    # Failure history (all, including resolved)
    if data["certs_failed"]:
        unresolved = get_unresolved_failures(data)
        resolved = {
            k: v for k, v in data["certs_failed"].items() if k not in unresolved
        }

        print("-" * 70)
        print("CERT FAILURE HISTORY")
        print("-" * 70)

        if unresolved:
            print(f"\n  UNRESOLVED ({len(unresolved)} certs still failing):")
            for ident, failures in sorted(unresolved.items()):
                last_ts, last_err = failures[-1]
                print(f"    {ident} — {len(failures)} failures, last {ts_to_str(last_ts)}")
                print(f"      {last_err[:150]}")

        if resolved:
            print(f"\n  RESOLVED ({len(resolved)} certs recovered after failures):")
            for ident, failures in sorted(resolved.items()):
                success_ts = data["certs_obtained"].get(ident, 0)
                print(f"    {ident} — {len(failures)} failures, then obtained {ts_to_str(success_ts)}")
        print()

    # Issues section
    print("-" * 70)
    print("CURRENT ISSUES")
    print("-" * 70)
    if not print_issues(data):
        print("  No current issues found.")
    print()

    # Error count summary
    error_msgs = defaultdict(int)
    for ts, logger, msg, err in data["errors"]:
        error_msgs[f"{logger}: {msg}"] += 1
    if error_msgs:
        print("-" * 70)
        print("ERROR SUMMARY (by type)")
        print("-" * 70)
        for key, count in sorted(error_msgs.items(), key=lambda x: -x[1]):
            print(f"  {count:>4}x  {key}")
        print()

    # TLS warnings summary (unique)
    if data["warnings"]:
        print("-" * 70)
        print(f"TLS WARNINGS ({len(data['warnings'])} total, showing unique)")
        print("-" * 70)
        seen = set()
        for ts, logger, msg, err in data["warnings"]:
            key = f"{logger}:{msg}:{err[:80]}"
            if key not in seen:
                seen.add(key)
                detail = err[:150] if err else msg
                print(f"  {ts_to_str(ts)}  [{logger}] {detail}")
        print()


def main():
    cron_mode = "--cron" in sys.argv
    filepath = None

    if "--file" in sys.argv:
        idx = sys.argv.index("--file")
        if idx + 1 >= len(sys.argv):
            print("Error: --file requires a path argument", file=sys.stderr)
            sys.exit(2)
        filepath = sys.argv[idx + 1]

    data = analyze(filepath)

    if cron_mode:
        has_issues = print_issues(data)
        sys.exit(1 if has_issues else 0)
    else:
        print_full_stats(data)


if __name__ == "__main__":
    main()
