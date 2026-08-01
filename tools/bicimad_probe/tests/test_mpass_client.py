from __future__ import annotations

import copy
import contextlib
import io
import json
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest import mock

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import fetch_trips_with_login  # noqa: E402
from mpass_client import (  # noqa: E402
    FlowResult,
    ProbeRequestError,
    build_login_device_model,
    fetch_trips,
    fetch_userdata_dn,
    login,
    run_login_trip_flow,
)


class MPassClientTests(unittest.TestCase):
    def test_login_success(self) -> None:
        opener = FakeOpener([FakeResponse(_login_payload())])

        result = login(
            email="person@example.test",
            password="fake-password",
            pass_key="fake-pass-key",
            x_client_id="fake-client-id",
            device_id="fake-device-id",
            login_device_model=build_login_device_model("Model X", "13"),
            opener=opener,
        )

        self.assertEqual(result.access_token, "fake-access-token")
        self.assertEqual(result.user_id, "fake-user-id")
        self.assertEqual(result.token_sec_expiration, 2592000)
        self.assertEqual(len(opener.requests), 1)
        request = opener.requests[0]
        self.assertEqual(request.get_method(), "POST")
        self.assertEqual(
            json.loads(request.data.decode("utf-8")),
            {
                "email": "person@example.test",
                "passKey": "fake-pass-key",
                "password": "fake-password",
                "X-ClientId": "fake-client-id",
            },
        )
        self.assertNotIn("latitude", request.headers)
        self.assertNotIn("longitude", request.headers)

    def test_login_with_non_success_code_fails_safely(self) -> None:
        opener = FakeOpener(
            [FakeResponse({"code": "99", "description": "login rejected", "data": []})]
        )

        with self.assertRaises(ProbeRequestError) as raised:
            _call_login(opener)

        self.assertEqual(raised.exception.stage, "login")
        self.assertEqual(raised.exception.status, 200)
        self.assertEqual(raised.exception.api_code, "99")
        self.assertEqual(raised.exception.error_type, "ApiError")

    def test_login_without_data_fails_safely(self) -> None:
        opener = FakeOpener([FakeResponse({"code": "00", "description": "ok"})])

        with self.assertRaises(ProbeRequestError) as raised:
            _call_login(opener)

        self.assertEqual(raised.exception.stage, "login")
        self.assertEqual(raised.exception.error_type, "InvalidResponse")

    def test_userdata_extracts_ds_dn(self) -> None:
        opener = FakeOpener(
            [
                FakeResponse(
                    {
                        "code": "00",
                        "description": "ok",
                        "data": {"DS_DN": "fake-dn-format", "DS_NIF": "ignored"},
                    }
                )
            ]
        )

        dn = fetch_userdata_dn(
            access_token="fake-access-token",
            email="person@example.test",
            user_id="fake-user-id",
            device_id="fake-device-id",
            device_model="Model X",
            opener=opener,
        )

        self.assertEqual(dn, "fake-dn-format")

    def test_userdata_accepts_code_01_with_ds_dn(self) -> None:
        opener = FakeOpener(
            [
                FakeResponse(
                    {
                        "code": "01",
                        "description": "El usuario tiene contratos",
                        "data": {"DS_DN": "fake-dn-format", "DS_NIF": "ignored"},
                    }
                )
            ]
        )

        dn = fetch_userdata_dn(
            access_token="fake-access-token",
            email="person@example.test",
            user_id="fake-user-id",
            device_id="fake-device-id",
            device_model="Model X",
            opener=opener,
        )

        self.assertEqual(dn, "fake-dn-format")

    def test_userdata_accepts_code_00_with_ds_dn(self) -> None:
        opener = FakeOpener(
            [
                FakeResponse(
                    {
                        "code": "00",
                        "description": "ok",
                        "data": {"DS_DN": "fake-dn-format"},
                    }
                )
            ]
        )

        dn = fetch_userdata_dn(
            access_token="fake-access-token",
            email="person@example.test",
            user_id="fake-user-id",
            device_id="fake-device-id",
            device_model="Model X",
            opener=opener,
        )

        self.assertEqual(dn, "fake-dn-format")

    def test_userdata_rejects_unexpected_code_safely(self) -> None:
        opener = FakeOpener(
            [
                FakeResponse(
                    {
                        "code": "77",
                        "description": "unexpected fake response",
                        "data": {"DS_DN": "fake-dn-format"},
                    }
                )
            ]
        )

        with self.assertRaises(ProbeRequestError) as raised:
            fetch_userdata_dn(
                access_token="fake-access-token",
                email="person@example.test",
                user_id="fake-user-id",
                device_id="fake-device-id",
                device_model="Model X",
                opener=opener,
            )

        self.assertEqual(raised.exception.stage, "userdata")
        self.assertEqual(raised.exception.status, 200)
        self.assertEqual(raised.exception.api_code, "77")
        self.assertEqual(raised.exception.error_type, "ApiError")

    def test_userdata_without_ds_dn_fails_safely(self) -> None:
        opener = FakeOpener(
            [
                FakeResponse(
                    {
                        "code": "01",
                        "description": "El usuario tiene contratos",
                        "data": {},
                    }
                )
            ]
        )

        with self.assertRaises(ProbeRequestError) as raised:
            fetch_userdata_dn(
                access_token="fake-access-token",
                email="person@example.test",
                user_id="fake-user-id",
                device_id="fake-device-id",
                device_model="Model X",
                opener=opener,
            )

        self.assertEqual(raised.exception.stage, "userdata")
        self.assertEqual(raised.exception.error_type, "MissingRequiredField")

    def test_userdata_requires_data_object(self) -> None:
        opener = FakeOpener(
            [
                FakeResponse(
                    {
                        "code": "01",
                        "description": "El usuario tiene contratos",
                        "data": [{"DS_DN": "fake-dn-format"}],
                    }
                )
            ]
        )

        with self.assertRaises(ProbeRequestError) as raised:
            fetch_userdata_dn(
                access_token="fake-access-token",
                email="person@example.test",
                user_id="fake-user-id",
                device_id="fake-device-id",
                device_model="Model X",
                opener=opener,
            )

        self.assertEqual(raised.exception.stage, "userdata")
        self.assertEqual(raised.exception.error_type, "InvalidResponse")

    def test_trips_success(self) -> None:
        trips_payload = _trips_payload()
        opener = FakeOpener([FakeResponse(trips_payload)])

        response = fetch_trips(
            access_token="fake-access-token",
            email="person@example.test",
            user_id="fake-user-id",
            nif="fake-dn-format",
            device_id="fake-device-id",
            device_model="Model X",
            opener=opener,
        )

        self.assertEqual(response.status, 200)
        self.assertEqual(response.payload["code"], "00")
        self.assertEqual(len(response.payload["data"]), 2)

    def test_http_error_in_each_stage_is_safe(self) -> None:
        cases = [
            ("login", lambda opener: _call_login(opener)),
            (
                "userdata",
                lambda opener: fetch_userdata_dn(
                    access_token="fake-access-token",
                    email="person@example.test",
                    user_id="fake-user-id",
                    device_id="fake-device-id",
                    device_model="Model X",
                    opener=opener,
                ),
            ),
            (
                "trips",
                lambda opener: fetch_trips(
                    access_token="fake-access-token",
                    email="person@example.test",
                    user_id="fake-user-id",
                    nif="fake-dn-format",
                    device_id="fake-device-id",
                    device_model="Model X",
                    opener=opener,
                ),
            ),
        ]

        for stage, action in cases:
            with self.subTest(stage=stage):
                opener = FakeOpener([_http_error(403)])
                with self.assertRaises(ProbeRequestError) as raised:
                    action(opener)
                self.assertEqual(raised.exception.stage, stage)
                self.assertEqual(raised.exception.status, 403)
                self.assertEqual(raised.exception.api_code, "41")
                self.assertEqual(raised.exception.error_type, "HTTPError")
                self.assertNotIn("fake-access-token", str(raised.exception))

    def test_full_flow_writes_only_normalized_json(self) -> None:
        trips_payload = _trips_payload()
        original_trips_payload = copy.deepcopy(trips_payload)
        opener = FakeOpener(
            [
                FakeResponse(_login_payload()),
                FakeResponse(_userdata_payload()),
                FakeResponse(trips_payload),
            ]
        )

        with tempfile.TemporaryDirectory() as directory:
            output_path = Path(directory) / "private" / "trips_normalized.json"
            result = run_login_trip_flow(
                email="person@example.test",
                password="fake-password",
                pass_key="fake-pass-key",
                x_client_id="fake-client-id",
                device_id="fake-device-id",
                device_model_visible="Model X",
                android_version="13",
                output_path=output_path,
                opener=opener,
            )

            self.assertEqual(result.received_count, 2)
            self.assertEqual(result.normalized_count, 2)
            files = [path for path in Path(directory).rglob("*") if path.is_file()]
            self.assertEqual(files, [output_path])
            normalized = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(
                set(normalized[0].keys()),
                {
                    "external_id",
                    "origin_station_number",
                    "origin_station_name",
                    "destination_station_number",
                    "destination_station_name",
                    "started_at",
                    "ended_at",
                    "duration_minutes",
                    "duration_text",
                },
            )
            self.assertNotIn("fake-user-id", json.dumps(normalized))
            self.assertNotIn("fake-device-id", json.dumps(normalized))
            self.assertEqual(trips_payload, original_trips_payload)
            self.assertEqual(len(opener.requests), 3)

    def test_interactive_output_does_not_include_secrets(self) -> None:
        result = FlowResult(
            token_sec_expiration=2592000,
            trips_status=200,
            trips_api_code="00",
            received_count=2,
            normalized_count=2,
            output_path=Path("tools/bicimad_probe/private/trips_normalized.json"),
        )
        secret_values = [
            "person@example.test",
            "fake-password",
            "fake-pass-key",
            "fake-client-id",
            "fake-device-id",
        ]

        stdout = io.StringIO()
        with mock.patch("builtins.input", side_effect=["person@example.test", "", ""]):
            with mock.patch(
                "getpass.getpass",
                side_effect=[
                    "fake-password",
                    "fake-pass-key",
                    "fake-client-id",
                    "fake-device-id",
                ],
            ):
                with mock.patch(
                    "fetch_trips_with_login.run_login_trip_flow",
                    return_value=result,
                ):
                    with contextlib.redirect_stdout(stdout):
                        exit_code = fetch_trips_with_login.main()

        output = stdout.getvalue()
        self.assertEqual(exit_code, 0)
        for secret in secret_values:
            self.assertNotIn(secret, output)
        self.assertIn("Login MPass: correcto", output)
        self.assertIn("Archivo generado:", output)

    def test_safe_error_output_does_not_include_nif_or_full_response(self) -> None:
        error = ProbeRequestError(
            stage="userdata",
            status=200,
            api_code="01",
            api_description="El usuario tiene contratos",
            error_type="MissingRequiredField",
        )

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            fetch_trips_with_login._print_safe_error(error)

        output = stdout.getvalue()
        self.assertIn("Etapa fallida: userdata", output)
        self.assertIn("Codigo de API: 01", output)
        self.assertNotIn("fake-dn-format", output)
        self.assertNotIn("DS_DN", output)
        self.assertNotIn("DS_NIF", output)
        self.assertNotIn("{", output)
        self.assertNotIn("}", output)


class FakeResponse:
    def __init__(self, payload: dict, status: int = 200) -> None:
        self.payload = payload
        self.status = status

    def __enter__(self) -> "FakeResponse":
        return self

    def __exit__(self, exc_type, exc_value, traceback) -> None:
        return None

    def read(self) -> bytes:
        return json.dumps(self.payload).encode("utf-8")


class FakeOpener:
    def __init__(self, responses: list[FakeResponse | Exception]) -> None:
        self.responses = responses
        self.requests = []

    def __call__(self, request, timeout: int):
        self.requests.append(request)
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response


def _call_login(opener: FakeOpener) -> None:
    login(
        email="person@example.test",
        password="fake-password",
        pass_key="fake-pass-key",
        x_client_id="fake-client-id",
        device_id="fake-device-id",
        login_device_model=build_login_device_model("Model X", "13"),
        opener=opener,
    )


def _http_error(status: int) -> urllib.error.HTTPError:
    return urllib.error.HTTPError(
        url="https://example.test",
        code=status,
        msg="Forbidden",
        hdrs={},
        fp=io.BytesIO(
            json.dumps({"code": "41", "description": "request rejected"}).encode(
                "utf-8"
            )
        ),
    )


def _login_payload() -> dict:
    return {
        "code": "00",
        "description": "ok",
        "data": [
            {
                "accessToken": "fake-access-token",
                "accessTokenCryp": "ignored",
                "idUser": "fake-user-id",
                "tokenSecExpiration": 2592000,
            }
        ],
    }


def _userdata_payload() -> dict:
    return {
        "code": "00",
        "description": "ok",
        "data": {
            "DS_DN": "fake-dn-format",
            "DS_NIF": "ignored",
            "name": "ignored",
        },
    }


def _trips_payload() -> dict:
    return {
        "code": "00",
        "description": "ok",
        "data": [
            {
                "trip_id": "fake-trip-001",
                "userId": "fake-user-id",
                "id_bike": "fake-bike",
                "payment": {"amount": 1.25},
                "undock": {
                    "undock_station_number": "90",
                    "undock_station_name": "Manuel Becerra",
                    "undock_ts": "2026-07-31T08:16:00+02:00",
                },
                "dock": {
                    "dock_station_number": "101",
                    "dock_station_name": "Felipe II",
                    "dock_ts": "2026-07-31T08:22:48+02:00",
                },
                "trip_minutes": 6.8,
                "trip_interval": "00:06:48",
            },
            {
                "trip_id": "fake-trip-002",
                "locator": "fake-locator",
                "undock": {
                    "undock_station_number": "49",
                    "undock_station_name": "",
                    "undock_ts": "2026-07-30T19:03:00+02:00",
                },
                "dock": {
                    "dock_station_number": "52",
                    "dock_station_name": "Puerta del Sol",
                    "dock_ts": "2026-07-30T19:15:34+02:00",
                },
                "trip_minutes": 12.566,
                "trip_interval": "00:12:34",
            },
        ],
    }


if __name__ == "__main__":
    unittest.main()
