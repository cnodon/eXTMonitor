import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).parents[1]/'macos'))
import setup as installer

class SetupTests(unittest.TestCase):
    def test_hdmi_does_not_download_receivers(self):
        with patch.object(installer,'download') as download,patch.object(installer,'ensure_adb') as adb:
            self.assertTrue(installer.install('hdmi','')['ok'])
            download.assert_not_called();adb.assert_not_called()

    def test_reject_invalid_tv_before_installing(self):
        with patch.object(installer,'install_app') as install:
            with self.assertRaises(ValueError):installer.install('sunshine','8.8.8.8')
            install.assert_not_called()

    def test_existing_receiver_is_preserved(self):
        with patch.object(installer.bridge,'run',return_value='package:/data/app/test.apk'),patch.object(installer,'download') as download:
            installer.install_apk('/adb','192.168.1.100','test.apk','local.extmonitor.tv')
            download.assert_not_called()

    def test_checksum_failure_never_promotes_download(self):
        with tempfile.TemporaryDirectory() as directory:
            cache=Path(directory)
            def fake_run(args,**kwargs):Path(args[-1]).write_bytes(b'wrong')
            with patch.object(installer,'CACHE',cache),patch.object(installer,'stage'),patch.object(installer.bridge,'run',side_effect=fake_run):
                with self.assertRaises(RuntimeError):installer.download({'name':'test.zip','digest':'sha256:'+'0'*64,'url':'https://example.test/file'})
            self.assertFalse((cache/'test.zip').exists())

    def test_all_downloads_are_pinned(self):
        for item in installer.LOCK:
            self.assertTrue(item['url'].startswith('https://'))
            self.assertRegex(item['digest'],r'^sha256:[0-9a-f]{64}$')

if __name__=='__main__':unittest.main()
