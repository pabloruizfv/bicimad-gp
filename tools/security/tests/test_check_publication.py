from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_publication import audit, private_path, scan


class PublicationTest(unittest.TestCase):
    def test_private_artifacts_and_official_data_exception(self):
        for path in ("local_secrets.json", "output/app.apk", "release/signing.jks",
                     "tools/bicimad_probe/private/capture.json", "backup/personal.sqlite",
                     ".env.production", "data.sqlite-wal"):
            self.assertTrue(private_path(path), path)
        for path in ("local_secrets.example.json", "tools/bicimad_probe/local_secrets.py",
                     "assets/data/legacy_route_models.sqlite", ".env.example",
                     "tools/bicimad_probe/private/.gitkeep"):
            self.assertFalse(private_path(path), path)

    def test_findings_never_include_matched_values(self):
        private = b"test-private-configuration-value"
        findings = scan(b"\0" + private, "test.png", [private])
        self.assertTrue(findings)
        self.assertNotIn(private.decode(), repr(findings))
        key = b"sb_" + b"secret_" + b"x" * 32
        self.assertTrue(scan(key, "config", []))
        self.assertNotIn(key.decode(), repr(scan(key, "config", [])))

    def test_deleted_secret_still_detected_in_history_and_index_is_separate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.run(
                    ["git", "-C", directory, *args], check=True,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                )
            git("init")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.invalid")
            secret = "sb_" + "secret_" + "a" * 32
            source = root / "config.txt"
            source.write_text(secret)
            git("add", "config.txt")
            git("-c", "commit.gpgsign=false", "commit", "-m", "fixture")
            source.write_text("safe")
            self.assertFalse(audit(root, staged=False, history=False))
            self.assertTrue(audit(root, staged=True, history=False))
            git("add", "config.txt")
            git("-c", "commit.gpgsign=false", "commit", "-m", "remove fixture")
            findings = audit(root, staged=True, history=True)
            self.assertTrue(any(f.location.startswith("HISTORY:") for f in findings))
            self.assertNotIn(secret, repr(findings))

    def test_gitignore_keeps_examples_but_excludes_secrets_and_builds(self):
        repo = Path(__file__).resolve().parents[3]
        for path in ("local_secrets.json", "dist/app.apk", "signing/release.jks",
                     "personal.sqlite", "tools/bicimad_probe/private/session.json"):
            result = subprocess.run(
                ["git", "-C", str(repo), "check-ignore", "--no-index", "-q", path],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            self.assertEqual(result.returncode, 0, path)
        for path in ("local_secrets.example.json", "assets/data/legacy_route_models.sqlite"):
            result = subprocess.run(
                ["git", "-C", str(repo), "check-ignore", "--no-index", "-q", path],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            self.assertEqual(result.returncode, 1, path)


if __name__ == "__main__":
    unittest.main()
