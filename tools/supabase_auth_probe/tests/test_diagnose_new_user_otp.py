import io
import json
import tempfile
import unittest
from pathlib import Path

from tools.supabase_auth_probe.diagnose_new_user_otp import (
    ProbeConfigError,
    PublicSupabaseConfig,
    load_public_config,
    normalize_email,
    send_signup_otp,
)


class _FakeResponse:
    def __init__(self, status=200):
        self.status = status

    def getcode(self):
        return self.status

    def read(self):
        return b"{}"

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return None


class SupabaseAuthProbeTests(unittest.TestCase):
    def test_normalizes_email(self):
        self.assertEqual(normalize_email(" Test.User@Example.COM "), "test.user@example.com")
        self.assertIsNone(normalize_email("invalid"))

    def test_loads_only_public_configuration(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "local_secrets.json"
            path.write_text(
                json.dumps(
                    {
                        "SUPABASE_URL": "https://project.example.test",
                        "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_fake",
                        "UNRELATED_SECRET": "must-not-be-used",
                    }
                ),
                encoding="utf-8",
            )
            config = load_public_config(path)

        self.assertEqual(config.url, "https://project.example.test")
        self.assertEqual(config.publishable_key, "sb_publishable_fake")

    def test_rejects_secret_key(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "local_secrets.json"
            path.write_text(
                json.dumps(
                    {
                        "SUPABASE_URL": "https://project.example.test",
                        "SUPABASE_PUBLISHABLE_KEY": "sb_secret_fake",
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaises(ProbeConfigError):
                load_public_config(path)

    def test_sends_exactly_one_otp_request_without_verification(self):
        requests = []

        def fake_open(request, timeout):
            requests.append((request, timeout))
            return _FakeResponse()

        result = send_signup_otp(
            PublicSupabaseConfig(
                url="https://project.example.test",
                publishable_key="fake-publishable-key",
            ),
            "new.user@example.test",
            open_request=fake_open,
        )

        self.assertTrue(result.accepted)
        self.assertEqual(len(requests), 1)
        request, _ = requests[0]
        self.assertEqual(request.method, "POST")
        self.assertEqual(request.full_url, "https://project.example.test/auth/v1/otp")
        self.assertEqual(
            json.loads(request.data.decode("utf-8")),
            {"email": "new.user@example.test", "create_user": True},
        )
        self.assertNotIn("token", request.full_url)
        self.assertNotIn("verify", request.full_url)

    def test_does_not_print_or_persist_configuration(self):
        captured = io.StringIO()
        config = PublicSupabaseConfig(
            url="https://project.example.test",
            publishable_key="fake-sensitive-publishable-key",
        )

        result = send_signup_otp(
            config,
            "new.user@example.test",
            open_request=lambda request, timeout: _FakeResponse(),
        )
        captured.write(str(result))

        self.assertNotIn(config.publishable_key, captured.getvalue())
        self.assertNotIn("new.user@example.test", captured.getvalue())


if __name__ == "__main__":
    unittest.main()
