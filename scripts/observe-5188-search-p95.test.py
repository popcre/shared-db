"""Offline end-to-end checks for the observation script."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('observe-5188-search-p95.sh').resolve()


class ObservationTests(unittest.TestCase):
    def run_case(self, mode):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binaries = root / 'bin'
            binaries.mkdir()
            mocks = {
                'supabase': '''#!/bin/bash
mkdir -p supabase/.temp
printf 'postgres://user@localhost:5432/postgres' > supabase/.temp/pooler-url
''',
                'psql': '''#!/bin/bash
if [[ "$*" != *"set statement_timeout"* ]]; then
  echo 10.00
  exit 0
fi
case "$MODE" in
  error) echo 'ERROR:  42501: permission denied' >&2; exit 1 ;;
  config) echo 'ERROR:  22023: invalid parameter value' >&2; exit 1 ;;
  reset) echo 'server closed the connection unexpectedly' >&2; exit 2 ;;
  malformed) printf 'SET\\n123.45\\n'; exit 0 ;;
esac
count=0
[[ -f "$COUNTER" ]] && read -r count < "$COUNTER"
echo $((count + 1)) > "$COUNTER"
if [[ "$MODE" == all || ( "$MODE" == mixed && $count -lt 2 ) ]]; then
  echo 'ERROR:  57014: canceling statement due to statement timeout' >&2
  exit 1
fi
# Simulate psql command tags unless quiet mode was requested.
[[ "$*" == *'-qAt'* ]] || echo SET
echo 123.45
''',
            }
            for name, content in mocks.items():
                target = binaries / name
                target.write_text(content)
                target.chmod(0o755)
            output = root / 'shared-db-5188-observation'
            output.mkdir()
            (output / 'observation.json').write_text('{"stale": true}')
            result = subprocess.run(['bash', str(SCRIPT)], env={
                **os.environ, 'PATH': f'{binaries}:{os.environ["PATH"]}',
                'RUNNER_TEMP': str(root), 'TMPDIR': str(root),
                'SUPABASE_DB_PASSWORD': 'fake', 'MODE': mode,
                'COUNTER': str(root / 'counter'),
            }, capture_output=True, text=True)
            artifact = output / 'observation.json'
            return result, json.loads(artifact.read_text()) if artifact.exists() else None

    def test_complete_samples_and_quiet_command_tags(self):
        result, data = self.run_case('success')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(data['corpus_p95_ms'], 123.45)
        self.assertEqual(data['corpus_completed_samples'], 20)
        self.assertFalse(data['corpus_percentiles_are_lower_bounds'])

    def test_timeouts_are_counted_and_included_in_percentiles(self):
        result, data = self.run_case('mixed')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(data['corpus_timeout_samples'], 2)
        self.assertEqual(data['corpus_completed_samples'], 18)
        self.assertEqual(data['corpus_p95_ms'], 45000)
        self.assertTrue(data['corpus_percentiles_are_lower_bounds'])
        self.assertIn('statement timeout', result.stderr)

    def test_all_timeouts_fail_without_artifact(self):
        result, data = self.run_case('all')
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(data)
        self.assertIn('all 20 samples timed out', result.stderr)

    def test_other_errors_and_malformed_output_fail(self):
        for mode in ('error', 'config', 'reset', 'malformed'):
            with self.subTest(mode=mode):
                result, data = self.run_case(mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertIsNone(data)
                self.assertTrue(result.stderr)


if __name__ == '__main__':
    unittest.main()
