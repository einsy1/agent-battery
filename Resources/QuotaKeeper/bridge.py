import contextlib
import io
import json
import sys
import re
import quota_keeper as keeper

output = io.StringIO()
error = None
try:
    with contextlib.redirect_stdout(output):
        keeper.check(trigger=sys.argv[1:] == ['tick'])
except Exception as exc:
    error = str(exc)
state_file = keeper.DATA / 'state.json'
try:
    state = json.loads(state_file.read_text()) if state_file.exists() else {}
except Exception:
    state = {}
message = output.getvalue().strip()
message = re.sub(r'^\d{4}-\d{2}-\d{2}T\S+ ', '', message)
message = re.sub(r'(重置：)\d{4}-\d{2}-\d{2}T(\d{2}:\d{2}):\d{2}[+-]\d{2}:\d{2}', r'\1\2', message)
print(json.dumps({'message': error or message, 'failed': error is not None,
                  'lastAttempt': state.get('last_attempt'), 'outcome': state.get('outcome')}))
