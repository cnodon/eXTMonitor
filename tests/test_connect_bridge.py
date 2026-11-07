import importlib.util
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('bridge',Path(__file__).parents[1]/'macos/bridge.py')
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)

class BridgeTests(unittest.TestCase):
    def test_reject_remote_and_command_addresses(self):
        for value in ['8.8.8.8','127.0.0.1','::1','0.0.0.0','192.168.1.100;id']:
            with self.assertRaises(ValueError):b.validate_tv(value)
        self.assertEqual(b.validate_tv('192.168.1.100'),'192.168.1.100')

    def test_busy_external_service_is_preserved(self):
        with patch.object(b,'app_running',return_value=True),patch.object(b,'stop') as stop:
            with self.assertRaises(RuntimeError):b.connect({'owned':False},'sunshine',b.TV_DEFAULT)
            stop.assert_not_called()

    def test_offline_tv_still_cleans_local_session(self):
        state={'owned':True,'display_owned':True,'mode':'sunshine','tv':b.TV_DEFAULT}
        with patch.object(b,'adb',side_effect=TimeoutError),patch.object(b,'quit_owned') as quit,patch.object(b,'remove_display') as remove,patch.object(b,'write_json'):
            b.stop(state)
            quit.assert_called_once();remove.assert_called_once()
            self.assertFalse(state['owned']);self.assertIn('未确认',state['error'])

    def test_failed_local_cleanup_keeps_ownership(self):
        state={'owned':True,'mode':'sunshine','tv':b.TV_DEFAULT}
        with patch.object(b,'adb'),patch.object(b,'quit_owned',side_effect=RuntimeError('running')),patch.object(b,'write_json') as write:
            with self.assertRaises(RuntimeError):b.stop(state)
            self.assertTrue(state['owned']);write.assert_not_called()

    def test_remove_only_owned_virtual_display(self):
        with patch.object(b,'displays',return_value=[{'id':2,'name':'Samsung','virtual':False},{'id':6,'name':'DDMM-TV','virtual':True}]),patch.object(b,'simple') as command:
            b.remove_display({'display_owned':False});command.assert_not_called()
            b.remove_display({'display_owned':True});command.assert_called_once_with('simpledisplay://remove?id=6')

    def test_metrics_expire_even_when_log_keeps_growing(self):
        now=time.strftime('%H:%M:%S')+'.000'
        old=time.strftime('%H:%M:%S',time.localtime(time.time()-90))+'.000'
        self.assertEqual(b.parse_open_stats(f'[{now}] PHONE-STATS {{"fps":59.8}} | mac enc=0')['fps'],59.8)
        self.assertEqual(b.parse_open_stats(f'[{old}] PHONE-STATS {{"fps":60}} | mac enc=0\n[{now}] connecting'),{})
        self.assertEqual(b.parse_open_stats('PHONE-STATS {"fps":60} |'),{})

    def test_idle_never_claims_target_fps(self):
        result=b.status({'owned':False,'phase':'idle'})
        self.assertIsNone(result['fps']);self.assertIsNone(result['bitrate']);self.assertEqual(result['phase'],'idle')

    def test_video_stats_survive_separate_adb_disconnect(self):
        with tempfile.TemporaryDirectory() as directory:
            home=Path(directory);log=home/'Library/Logs/OpenDisplay/opendisplay.log'
            log.parent.mkdir(parents=True)
            log.write_text('['+time.strftime('%H:%M:%S')+'.000] PHONE-STATS {"fps":30,"mbps":6.5} | mac enc=0\n')
            with patch.object(b.Path,'home',return_value=home),patch.object(b,'app_running',return_value=True),patch.object(b,'adb',side_effect=TimeoutError):
                result=b.status({'owned':True,'mode':'opendisplay','tv':b.TV_DEFAULT})
            self.assertEqual(result['phase'],'streaming');self.assertEqual(result['fps'],30)
            self.assertFalse(result['tv_control'])

    def test_virtual_screen_is_4k_pixels_not_8k(self):
        with patch.object(b,'displays',side_effect=[[],[{'name':'DDMM-TV','id':6,'virtual':True}]]),patch.object(b,'simple') as command:
            self.assertEqual(b.ensure_display(),6)
            self.assertIn('width=1920&height=1080',command.call_args.args[0])

if __name__=='__main__':unittest.main()
