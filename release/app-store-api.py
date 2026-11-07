#!/usr/bin/env python3
"""App Store Connect requests using local, ignored team-key credentials.
Usage: python3 release/app-store-api.py GET /v1/apps [body.json] [output.json]
Never prints private keys, JWTs or upload URLs.
"""
import base64
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
credentials = json.loads((ROOT / '.sdk/app-store-connect/credentials.json').read_text())

def request(method, path, body=None):
    if not path.startswith('/v1/') and not path.startswith('/v2/'):
        raise ValueError('Only App Store Connect API paths are accepted')
    now = int(time.time())
    header = {'alg': 'ES256', 'kid': credentials['keyId'], 'typ': 'JWT'}
    payload = {'iss': credentials['issuerId'], 'iat': now, 'exp': now + 600, 'aud': 'appstoreconnect-v1'}
    unsigned = b'.'.join(base64.urlsafe_b64encode(json.dumps(x, separators=(',', ':')).encode()).rstrip(b'=') for x in [header, payload])
    signed = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', str(ROOT / credentials['keyPath'])], input=unsigned, capture_output=True, check=True).stdout
    # OpenSSL returns DER; JWT ES256 requires fixed-width R || S.
    if signed[0] != 0x30 or signed[2] != 0x02:
        raise ValueError('Unexpected ECDSA signature encoding')
    rlen = signed[3]; offset = 4 + rlen
    if signed[offset] != 0x02:
        raise ValueError('Unexpected ECDSA signature encoding')
    slen = signed[offset + 1]
    signature = int.from_bytes(signed[4:offset], 'big').to_bytes(32, 'big') + int.from_bytes(signed[offset+2:offset+2+slen], 'big').to_bytes(32, 'big')
    token = (unsigned + b'.' + base64.urlsafe_b64encode(signature).rstrip(b'=')).decode()
    req = urllib.request.Request('https://api.appstoreconnect.apple.com' + path, data=json.dumps(body).encode() if body is not None else None,
        headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json', 'Accept': 'application/json'}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=90) as response:
            data = response.read()
            return json.loads(data) if data else {}
    except urllib.error.HTTPError as e:
        errors = json.loads(e.read()).get('errors', [])
        raise RuntimeError(f'{method} {path}: HTTP {e.code}: ' + json.dumps(errors)) from None

if __name__ == '__main__':
    result = request(sys.argv[1], sys.argv[2], json.loads(Path(sys.argv[3]).read_text()) if len(sys.argv) > 3 and sys.argv[3] != '-' else None)
    if len(sys.argv) > 4:
        Path(sys.argv[4]).write_text(json.dumps(result, indent=2) + '\n')
        print('Response saved to', sys.argv[4])
    else:
        data = result.get('data', [])
        print('Request succeeded;', len(data) if isinstance(data, list) else 1, 'resource(s).')
