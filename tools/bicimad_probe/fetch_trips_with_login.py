#!/usr/bin/env python3
"""Run the local read-only BiciMAD experiment with an interactive MPass login."""

from __future__ import annotations

import getpass

from mpass_client import ProbeRequestError, run_login_trip_flow

DEFAULT_DEVICE_MODEL = "Samsung SM-A127F"
DEFAULT_ANDROID_VERSION = "13"


def main() -> int:
    try:
        values = _prompt_values()
        result = run_login_trip_flow(**values)
    except ProbeRequestError as error:
        _print_safe_error(error)
        return 1
    except (OSError, ValueError) as error:
        print("Etapa fallida: entrada")
        print("HTTP -")
        print(f"Tipo de excepcion: {type(error).__name__}")
        return 1

    print("Login MPass: correcto")
    expiration = (
        result.token_sec_expiration
        if result.token_sec_expiration is not None
        else "-"
    )
    print(f"Caducidad declarada del token: {expiration} segundos")
    print("Datos de usuario: correctos")
    print(f"HTTP viajes: {result.trips_status}")
    print(f"Codigo de API: {result.trips_api_code or '-'}")
    print(f"Viajes recibidos: {result.received_count}")
    print(f"Viajes normalizados: {result.normalized_count}")
    print(f"Archivo generado: {result.output_path.as_posix()}")
    return 0


def _prompt_values() -> dict[str, str]:
    email = input("Email: ").strip()
    password = getpass.getpass("Contraseña: ")
    pass_key = getpass.getpass("passKey: ")
    x_client_id = getpass.getpass("X-ClientId: ")
    device_id = getpass.getpass("Device ID: ")
    device_model_visible = _input_default(
        "Device model visible",
        DEFAULT_DEVICE_MODEL,
    )
    android_version = _input_default("Versión de Android", DEFAULT_ANDROID_VERSION)

    values = {
        "email": email,
        "password": password,
        "pass_key": pass_key,
        "x_client_id": x_client_id,
        "device_id": device_id,
        "device_model_visible": device_model_visible,
        "android_version": android_version,
    }
    if any(not value for value in values.values()):
        raise ValueError("Missing required local input")
    return values


def _input_default(label: str, default: str) -> str:
    value = input(f"{label} [{default}]: ").strip()
    return value or default


def _print_safe_error(error: ProbeRequestError) -> None:
    print(f"Etapa fallida: {error.stage}")
    print(f"HTTP {error.status if error.status is not None else '-'}")
    if error.api_code is not None:
        print(f"Codigo de API: {error.api_code}")
    if error.api_description is not None:
        print(f"Descripcion: {error.api_description}")
    print(f"Tipo de excepcion: {error.error_type}")


if __name__ == "__main__":
    raise SystemExit(main())
