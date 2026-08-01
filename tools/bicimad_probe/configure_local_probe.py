#!/usr/bin/env python3
"""Store or remove local technical BiciMAD probe configuration."""

from __future__ import annotations

import argparse
import getpass

from local_secrets import clear_technical_config, save_technical_config


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Configure local technical credentials for the BiciMAD probe.",
    )
    parser.add_argument(
        "--clear",
        action="store_true",
        help="Remove stored passKey and X-ClientId entries.",
    )
    args = parser.parse_args(argv)

    if args.clear:
        clear_technical_config()
        print("Configuración técnica eliminada.")
        return 0

    pass_key = getpass.getpass("passKey: ")
    x_client_id = getpass.getpass("X-ClientId: ")
    save_technical_config(pass_key=pass_key, x_client_id=x_client_id)
    print("Configuración técnica almacenada correctamente.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
