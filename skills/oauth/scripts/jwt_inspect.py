#!/usr/bin/env python3
"""
jwt_inspect.py — Decode and inspect a JWT without verifying the signature.

Decodes the header and payload, pretty-prints all claims, and warns about:
  - Expired tokens (exp is in the past)
  - Tokens not yet valid (nbf is in the future)
  - Weak algorithm (HS256 — symmetric, should not be used for server verification)
  - Missing mandatory claims (exp, iss, aud, sub)
  - Algorithm 'none' (signature completely disabled)

Usage:
    python jwt_inspect.py <jwt_string>
    python jwt_inspect.py eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ1c2VyXzEyMyJ9.sig

WARNING: This tool does NOT verify the signature. Use it for debugging only.
         Never use this in production to make authorisation decisions.

Exit codes:
    0  Token decoded; no warnings
    1  Token decoded; one or more warnings found
    2  Could not decode the token (malformed input)
"""

import base64
import json
import sys
from datetime import datetime, timezone


ANSI_RED    = "\033[0;31m"
ANSI_YELLOW = "\033[1;33m"
ANSI_GREEN  = "\033[0;32m"
ANSI_CYAN   = "\033[0;36m"
ANSI_BOLD   = "\033[1m"
ANSI_RESET  = "\033[0m"


def b64url_decode(data: str) -> bytes:
    """Decode a Base64URL-encoded string, adding padding as needed."""
    padding = 4 - len(data) % 4
    if padding != 4:
        data += "=" * padding
    return base64.urlsafe_b64decode(data)


def decode_part(part: str, label: str) -> dict:
    """Decode a Base64URL-encoded JWT part and parse as JSON."""
    try:
        raw = b64url_decode(part)
    except Exception as e:
        print(f"ERROR: failed to base64url-decode {label}: {e}", file=sys.stderr)
        sys.exit(2)

    try:
        return json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"ERROR: {label} is not valid JSON: {e}", file=sys.stderr)
        sys.exit(2)


def format_timestamp(ts: int) -> str:
    """Convert a Unix timestamp to a human-readable UTC string."""
    try:
        dt = datetime.fromtimestamp(ts, tz=timezone.utc)
        return dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    except (OSError, OverflowError, ValueError):
        return f"<invalid timestamp: {ts}>"


def print_section(title: str) -> None:
    print(f"\n{ANSI_BOLD}{ANSI_CYAN}── {title} {'─' * max(0, 50 - len(title))}{ANSI_RESET}")


def print_json(data: dict) -> None:
    formatted = json.dumps(data, indent=2, ensure_ascii=False)
    print(formatted)


def warn(message: str) -> None:
    print(f"{ANSI_YELLOW}  WARNING: {message}{ANSI_RESET}")


def error(message: str) -> None:
    print(f"{ANSI_RED}  ERROR: {message}{ANSI_RESET}")


def ok(message: str) -> None:
    print(f"{ANSI_GREEN}  OK: {message}{ANSI_RESET}")


def inspect_header(header: dict) -> list[str]:
    """Validate the header and return a list of warning messages."""
    warnings: list[str] = []

    alg = header.get("alg", "")

    if alg == "none":
        warnings.append(
            "Algorithm is 'none' — signature verification is completely disabled. "
            "This token provides NO authenticity guarantees."
        )
    elif alg == "HS256":
        warnings.append(
            "Algorithm is HS256 (HMAC-SHA256) — this is a symmetric algorithm. "
            "The same key is used to sign and verify. If your service verifies HS256 tokens, "
            "an attacker who obtains the key can forge arbitrary tokens. "
            "Prefer RS256 or ES256 (asymmetric algorithms)."
        )
    elif alg in ("RS256", "RS384", "RS512", "ES256", "ES384", "ES512", "PS256", "PS384", "PS512"):
        pass  # Acceptable asymmetric algorithms
    elif alg:
        warnings.append(f"Unrecognised algorithm: {alg!r}. Verify this is an approved algorithm.")
    else:
        warnings.append("No 'alg' claim in header.")

    if "kid" not in header:
        warnings.append(
            "'kid' (Key ID) is missing from the header. "
            "Without kid, key rotation requires invalidating all tokens instead of just rotating the active key."
        )

    return warnings


def inspect_payload(payload: dict) -> list[str]:
    """Validate the payload and return a list of warning messages."""
    warnings: list[str] = []
    now = datetime.now(tz=timezone.utc).timestamp()

    # exp — expiry
    if "exp" not in payload:
        warnings.append("Missing 'exp' (expiry) claim — tokens without an expiry never expire.")
    else:
        exp = payload["exp"]
        if not isinstance(exp, (int, float)):
            warnings.append(f"'exp' is not a number: {exp!r}")
        elif now > exp:
            expired_at = format_timestamp(int(exp))
            elapsed_seconds = int(now - exp)
            elapsed_str = (
                f"{elapsed_seconds // 3600}h {(elapsed_seconds % 3600) // 60}m {elapsed_seconds % 60}s"
                if elapsed_seconds >= 3600
                else f"{elapsed_seconds // 60}m {elapsed_seconds % 60}s"
                if elapsed_seconds >= 60
                else f"{elapsed_seconds}s"
            )
            warnings.append(
                f"Token is EXPIRED. 'exp' was {expired_at} ({elapsed_str} ago)."
            )

    # nbf — not before
    if "nbf" in payload:
        nbf = payload["nbf"]
        if isinstance(nbf, (int, float)) and now < nbf:
            valid_from = format_timestamp(int(nbf))
            warnings.append(f"Token is NOT YET VALID. 'nbf' is {valid_from} (in the future).")

    # iss — issuer
    if "iss" not in payload:
        warnings.append(
            "Missing 'iss' (issuer) claim. "
            "Without iss, you cannot verify the token came from your expected authorization server."
        )

    # aud — audience
    if "aud" not in payload:
        warnings.append(
            "Missing 'aud' (audience) claim. "
            "Without aud, a token issued for one service can be replayed against another."
        )

    # sub — subject
    if "sub" not in payload:
        warnings.append("Missing 'sub' (subject) claim — the token does not identify a principal.")

    return warnings


def summarise_claims(payload: dict) -> None:
    """Print a human-readable summary of key claims."""
    print_section("Claim Summary")

    now = datetime.now(tz=timezone.utc).timestamp()

    for claim, label in [("sub", "Subject"), ("iss", "Issuer"), ("aud", "Audience"), ("jti", "JWT ID")]:
        if claim in payload:
            print(f"  {label:15}: {payload[claim]}")

    for claim, label in [("iat", "Issued at"), ("exp", "Expires"), ("nbf", "Not before"), ("auth_time", "Auth time")]:
        if claim in payload:
            ts = payload[claim]
            if isinstance(ts, (int, float)):
                human = format_timestamp(int(ts))
                if claim == "exp":
                    remaining = ts - now
                    if remaining > 0:
                        status = f"{ANSI_GREEN}valid for {int(remaining)}s{ANSI_RESET}"
                    else:
                        status = f"{ANSI_RED}EXPIRED {int(-remaining)}s ago{ANSI_RESET}"
                    print(f"  {label:15}: {human} ({status})")
                else:
                    print(f"  {label:15}: {human}")
            else:
                print(f"  {label:15}: {ts}")

    for claim in ("scope", "scp"):
        if claim in payload:
            scopes = payload[claim]
            if isinstance(scopes, list):
                scopes = " ".join(scopes)
            print(f"  {'Scopes':15}: {scopes}")


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python jwt_inspect.py <jwt_string>", file=sys.stderr)
        print("       echo $TOKEN | python jwt_inspect.py -", file=sys.stderr)
        sys.exit(2)

    token_input = sys.argv[1]

    if token_input == "-":
        token_input = sys.stdin.read().strip()

    # Strip "Bearer " prefix if present
    if token_input.lower().startswith("bearer "):
        token_input = token_input[7:]

    token_input = token_input.strip()

    parts = token_input.split(".")
    if len(parts) != 3:
        print(
            f"ERROR: expected 3 dot-separated parts (header.payload.signature), "
            f"got {len(parts)}.",
            file=sys.stderr,
        )
        sys.exit(2)

    header_raw, payload_raw, signature_raw = parts

    header = decode_part(header_raw, "header")
    payload = decode_part(payload_raw, "payload")

    print(f"\n{ANSI_BOLD}JWT Inspector{ANSI_RESET}  {ANSI_YELLOW}(signature NOT verified){ANSI_RESET}")

    print_section("Header")
    print_json(header)

    print_section("Payload")
    print_json(payload)

    print_section("Signature")
    print(f"  {signature_raw[:32]}..." if len(signature_raw) > 32 else f"  {signature_raw}")
    print(f"  (length: {len(signature_raw)} base64url chars)")

    summarise_claims(payload)

    header_warnings = inspect_header(header)
    payload_warnings = inspect_payload(payload)
    all_warnings = header_warnings + payload_warnings

    if all_warnings:
        print_section("Warnings")
        for w in all_warnings:
            warn(w)
        print()
        sys.exit(1)
    else:
        print_section("Checks")
        ok("No structural warnings found.")
        print(f"  {ANSI_YELLOW}Remember: signature was NOT verified.{ANSI_RESET}")
        print()
        sys.exit(0)


if __name__ == "__main__":
    main()
