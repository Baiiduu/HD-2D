"""Read an existing Meowa job through the bundled runner; no submission or download."""
import argparse
import importlib.util
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--job-id', required=True)
args = parser.parse_args()
spec = importlib.util.spec_from_file_location('meowa_api_test_runner', r'C:\Users\PC\.codex\skills\game-assets\meowart_api.py')
api = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = api
spec.loader.exec_module(api)
try:
    payload = api.poll_job(api_base=api.DEFAULT_API_BASE, api_key=api._resolve_auth_token(),
                           api_job_id=args.job_id, timeout=20, verify=True)
    print(api._format_json_for_display(payload))
except Exception as error:
    print('[ERROR] ' + str(error))
    sys.exit(1)
