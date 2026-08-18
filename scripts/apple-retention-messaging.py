#!/usr/bin/env python3
"""Manage Baseball's Apple Retention Messaging sandbox configuration."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

try:
    import jwt
except ImportError as exc:  # pragma: no cover - environment setup failure
    raise SystemExit("error: install PyJWT and cryptography before running this script") from exc


BUNDLE_ID = "com.jackwallner.baseball"
PRODUCTS = {
    "yearly": "com.jackwallner.baseball.pro.yearly",
    "monthly": "com.jackwallner.baseball.pro.monthly",
}
MESSAGES = {
    "yearly": {
        "id": "011d8acb-3ea0-5c98-bdd4-6d72ab531072",
        "header": "Keep your full scouting toolkit",
        "body": "Keep historical seasons, recent form, and player comparisons in StatScout+ for your next scouting session.",
    },
    "monthly": {
        "id": "252b8604-d259-5318-a6f2-dcce30824529",
        "header": "Stay ready for the next series",
        "body": "Keep current player trends, comparisons, and historical seasons available whenever you scout.",
    },
}

SANDBOX_BASE_URL = "https://api.storekit-sandbox.apple.com/inApps/v1/messaging"
PRODUCTION_BASE_URL = "https://api.storekit.apple.com/inApps/v1/messaging"
SANDBOX_REQUEST_INTERVAL_SECONDS = 11.0


def load_credentials() -> tuple[str, str, Path]:
    credentials_path = Path.home() / ".baseball_credentials"
    if credentials_path.exists():
        for line in credentials_path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            if line.startswith("export "):
                line = line[7:].lstrip()
            key, value = line.split("=", 1)
            value = value.strip().strip('"').strip("'")
            os.environ.setdefault(key.strip(), os.path.expandvars(value))

    key_id = os.environ.get("APPLE_IAP_KEY_ID") or os.environ.get("ASC_API_KEY_ID")
    issuer_id = os.environ.get("APPLE_IAP_ISSUER_ID") or os.environ.get("ASC_ISSUER_ID")
    key_path = os.environ.get("APPLE_IAP_KEY_PATH") or os.environ.get("ASC_KEY_PATH")
    if not key_id or not issuer_id or not key_path:
        raise SystemExit(
            "error: set APPLE_IAP_KEY_ID, APPLE_IAP_ISSUER_ID, and "
            "APPLE_IAP_KEY_PATH in ~/.baseball_credentials"
        )

    path = Path(key_path).expanduser()
    if not path.exists():
        raise SystemExit(f"error: Apple private key not found at {path}")
    return key_id, issuer_id, path


def bearer_token() -> str:
    key_id, issuer_id, key_path = load_credentials()
    issued_at = int(time.time())
    return jwt.encode(
        {
            "iss": issuer_id,
            "iat": issued_at,
            "exp": issued_at + 1200,
            "aud": "appstoreconnect-v1",
            "bid": BUNDLE_ID,
        },
        key_path.read_text(),
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


class AppleAPIError(RuntimeError):
    def __init__(self, status: int, payload: str):
        super().__init__(f"Apple API returned HTTP {status}: {payload}")
        self.status = status
        self.payload = payload


def request(environment: str, method: str, path: str, body: dict | None = None) -> dict:
    base_url = SANDBOX_BASE_URL if environment == "sandbox" else PRODUCTION_BASE_URL
    url = f"{base_url}{path}"
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Authorization": f"Bearer {bearer_token()}"}
    if body is not None:
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            raw = response.read().decode()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        payload = error.read().decode(errors="replace")
        raise AppleAPIError(error.code, payload) from error


def upload_messages(environment: str) -> None:
    for kind, message in MESSAGES.items():
        path = f"/message/{urllib.parse.quote(message['id'], safe='')}"
        try:
            request(
                environment,
                "PUT",
                path,
                {"header": message["header"], "body": message["body"]},
            )
            print(f"uploaded {kind} message {message['id']}")
        except AppleAPIError as error:
            if error.status == 409:
                print(f"message already exists: {kind} {message['id']}")
            else:
                raise
        if environment == "sandbox":
            time.sleep(SANDBOX_REQUEST_INTERVAL_SECONDS)


def configure_defaults(environment: str, locale: str) -> None:
    for kind, product_id in PRODUCTS.items():
        message_id = MESSAGES[kind]["id"]
        encoded_product = urllib.parse.quote(product_id, safe="")
        encoded_locale = urllib.parse.quote(locale, safe="")
        request(
            environment,
            "PUT",
            f"/default/{encoded_product}/{encoded_locale}",
            {"messageIdentifier": message_id},
        )
        print(f"configured {environment} default: {product_id} ({locale})")
        if environment == "sandbox":
            time.sleep(SANDBOX_REQUEST_INTERVAL_SECONDS)


def configure_url(environment: str, endpoint_url: str) -> None:
    if not endpoint_url.startswith("https://") or len(endpoint_url) > 256:
        raise SystemExit("error: endpoint URL must be HTTPS and no longer than 256 characters")
    request(environment, "PUT", "/realtime/url", {"realtimeURL": endpoint_url})
    print(f"configured {environment} endpoint: {endpoint_url}")


def list_status(environment: str) -> None:
    try:
        messages = request(environment, "GET", "/message/list")
    except AppleAPIError as error:
        if error.status == 404:
            print(
                f"{environment} Retention Messaging access is not enabled "
                "for this developer account or app."
            )
            return
        raise
    print(json.dumps(messages, indent=2, sort_keys=True))
    try:
        realtime_url = request(environment, "GET", "/realtime/url")
    except AppleAPIError as error:
        if error.status == 404:
            print(f"{environment} realtime URL: not configured")
        else:
            raise
    else:
        print(json.dumps(realtime_url, indent=2, sort_keys=True))


def initiate_performance_test(original_transaction_id: str) -> None:
    result = request(
        "sandbox",
        "POST",
        "/performanceTest",
        {"originalTransactionId": original_transaction_id},
    )
    print(json.dumps(result, indent=2, sort_keys=True))


def performance_test_results(request_id: str) -> None:
    result = request(
        "sandbox",
        "GET",
        f"/performanceTest/result/{urllib.parse.quote(request_id, safe='')}",
    )
    print(json.dumps(result, indent=2, sort_keys=True))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    setup = subparsers.add_parser(
        "setup-sandbox",
        help="upload messages, set defaults, and configure the sandbox URL",
    )
    setup.add_argument("--endpoint-url", required=True)
    setup.add_argument("--locale", default="en-US")

    upload = subparsers.add_parser("upload-messages")
    upload.add_argument("--environment", choices=("sandbox", "production"), default="sandbox")

    defaults = subparsers.add_parser("configure-defaults")
    defaults.add_argument("--environment", choices=("sandbox", "production"), default="sandbox")
    defaults.add_argument("--locale", default="en-US")

    configure = subparsers.add_parser("configure-url")
    configure.add_argument("--environment", choices=("sandbox", "production"), required=True)
    configure.add_argument("--endpoint-url", required=True)

    status = subparsers.add_parser("status")
    status.add_argument("--environment", choices=("sandbox", "production"), default="sandbox")

    performance = subparsers.add_parser("performance-test")
    performance.add_argument("original_transaction_id")

    results = subparsers.add_parser("performance-results")
    results.add_argument("request_id")

    return parser


def main() -> None:
    args = build_parser().parse_args()
    if args.command == "setup-sandbox":
        upload_messages("sandbox")
        configure_defaults("sandbox", args.locale)
        configure_url("sandbox", args.endpoint_url)
    elif args.command == "upload-messages":
        upload_messages(args.environment)
    elif args.command == "configure-defaults":
        configure_defaults(args.environment, args.locale)
    elif args.command == "configure-url":
        configure_url(args.environment, args.endpoint_url)
    elif args.command == "status":
        list_status(args.environment)
    elif args.command == "performance-test":
        initiate_performance_test(args.original_transaction_id)
    elif args.command == "performance-results":
        performance_test_results(args.request_id)


if __name__ == "__main__":
    try:
        main()
    except AppleAPIError as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1) from error
