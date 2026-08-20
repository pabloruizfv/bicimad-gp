#!/usr/bin/env python3
"""Isolated probe for Supabase email OTP signup behavior."""

from __future__ import annotations

import base64
import json
import re
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Callable
from urllib.parse import urlparse

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CONFIG_PATH = PROJECT_ROOT / "local_secrets.json"
TIMEOUT_SECONDS = 20


class ProbeConfigError(Exception):
    pass


@dataclass(frozen=True)
class PublicSupabaseConfig:
    url: str
    publishable_key: str


@dataclass(frozen=True)
class OtpProbeResult:
    accepted: bool
    status: int | None = None
    error_type: str | None = None
    api_code: str | None = None


def normalize_email(value: str) -> str | None:
    normalized = value.strip().lower()
    if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", normalized):
        return None
    return normalized


def load_public_config(path: Path = CONFIG_PATH) -> PublicSupabaseConfig:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ProbeConfigError("configuration_unavailable") from error
    if not isinstance(payload, dict):
        raise ProbeConfigError("configuration_invalid")

    url = str(payload.get("SUPABASE_URL") or "").strip()
    key = str(payload.get("SUPABASE_PUBLISHABLE_KEY") or "").strip()
    parsed_url = urlparse(url)
    if parsed_url.scheme not in {"http", "https"} or not parsed_url.netloc or not key:
        raise ProbeConfigError("configuration_incomplete")
    if _is_forbidden_secret_key(key):
        raise ProbeConfigError("non_publishable_key")
    return PublicSupabaseConfig(url=url, publishable_key=key)


def _is_forbidden_secret_key(key: str) -> bool:
    if key.startswith("sb_secret_"):
        return True
    parts = key.split(".")
    if len(parts) != 3:
        return False
    try:
        padding = "=" * (-len(parts[1]) % 4)
        payload = json.loads(
            base64.urlsafe_b64decode(parts[1] + padding).decode("utf-8")
        )
    except (ValueError, UnicodeError, json.JSONDecodeError):
        return False
    return isinstance(payload, dict) and payload.get("role") == "service_role"


class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def send_signup_otp(
    config: PublicSupabaseConfig,
    normalized_email: str,
    *,
    open_request: Callable[..., object] | None = None,
) -> OtpProbeResult:
    endpoint = config.url.rstrip("/") + "/auth/v1/otp"
    body = json.dumps(
        {"email": normalized_email, "create_user": True},
        separators=(",", ":"),
    ).encode("utf-8")
    request = urllib.request.Request(
        endpoint,
        data=body,
        method="POST",
        headers={
            "apikey": config.publishable_key,
            "Authorization": f"Bearer {config.publishable_key}",
            "Content-Type": "application/json",
        },
    )
    opener = open_request or urllib.request.build_opener(_NoRedirectHandler()).open
    try:
        response = opener(request, timeout=TIMEOUT_SECONDS)
        with response:
            status = int(getattr(response, "status", response.getcode()))
            response.read()
        if 200 <= status < 300:
            return OtpProbeResult(accepted=True, status=status)
        return OtpProbeResult(
            accepted=False,
            status=status,
            error_type="http_error",
        )
    except urllib.error.HTTPError as error:
        api_code = _safe_api_code(_read_error_code(error))
        return OtpProbeResult(
            accepted=False,
            status=error.code,
            error_type="http_error",
            api_code=api_code,
        )
    except urllib.error.URLError as error:
        return OtpProbeResult(
            accepted=False,
            error_type=type(error.reason).__name__,
        )
    except TimeoutError:
        return OtpProbeResult(accepted=False, error_type="TimeoutError")
    except Exception as error:
        return OtpProbeResult(accepted=False, error_type=type(error).__name__)


def _read_error_code(error: urllib.error.HTTPError) -> object:
    try:
        payload = json.loads(error.read().decode("utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return None
    if not isinstance(payload, dict):
        return None
    return payload.get("code") or payload.get("error_code")


def _safe_api_code(value: object) -> str | None:
    text = str(value or "")
    return text if re.fullmatch(r"[a-z0-9_]{1,64}", text) else None


def main() -> int:
    try:
        config = load_public_config()
    except ProbeConfigError as error:
        print(f"Solicitud OTP: error ({error})")
        return 1

    email = normalize_email(input("Email de prueba: "))
    if email is None:
        print("Solicitud OTP: error (email_invalid)")
        return 1

    result = send_signup_otp(config, email)
    if not result.accepted:
        details = [result.error_type or "unknown_error"]
        if result.status is not None:
            details.append(f"http_{result.status}")
        if result.api_code is not None:
            details.append(f"code_{result.api_code}")
        print(f"Solicitud OTP: error ({', '.join(details)})")
        return 1

    print("Solicitud OTP: aceptada.")
    print("Comprueba que has recibido un único correo para este intento.")
    print("Si el usuario es nuevo, comprueba la plantilla Confirm signup.")
    print("El correo debería mostrar un código OTP y no exigir abrir un enlace.")
    print("No introduzcas ni compartas el código fuera de la app de prueba.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
