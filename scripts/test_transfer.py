import os
import pathlib
import secrets
import subprocess
import tempfile
import time
import unittest
import urllib.request
import urllib.error

class TransferTest(unittest.TestCase):
    def test_authenticated_transfer(self):
        server = pathlib.Path(__file__).with_name('transfer_server.py')
        self.assertTrue(server.is_file(), 'authenticated server is missing')
        with tempfile.TemporaryDirectory() as d:
            pathlib.Path(d, 'fixture.bin').write_bytes(b'0123456789')
            pathlib.Path(d, 'link').symlink_to('/etc/passwd')
            token = secrets.token_hex(32)
            p = subprocess.Popen(['python3', str(server), d, '18765'], env={**os.environ, 'TRANSFER_TOKEN': token})
            try:
                time.sleep(.5)
                def req(path='/fixture.bin', auth=True, method='GET', rang=None):
                    headers = {'Authorization': 'Bearer '+token} if auth else {}
                    if rang: headers['Range'] = rang
                    try:
                        return urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:18765'+path, headers=headers, method=method))
                    except urllib.error.HTTPError as e: return e
                self.assertEqual(req(auth=False).status, 401)
                self.assertEqual(req().read(), b'0123456789')
                r = req(rang='bytes=4-'); self.assertEqual(r.status, 206); self.assertEqual(r.read(), b'456789')
                self.assertEqual(req(method='HEAD').headers['Content-Length'], '10')
                for path in ['/', '/link', '/../etc/passwd', '/%2e%2e/etc/passwd']:
                    self.assertEqual(req(path).status, 404)
                self.assertEqual(req(rang='bytes=99-').status, 416)
                self.assertEqual(req(method='POST').status, 405)
            finally:
                p.terminate(); p.wait(timeout=5)

if __name__ == '__main__': unittest.main()
