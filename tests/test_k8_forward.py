import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch, Mock
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('forward',ROOT/'k8-scripts/forward.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class ForwardTest(unittest.TestCase):
    def test_stale_tunnel_is_restarted_even_when_kubectl_stays_alive(self):
        child=Mock();child.poll.return_value=None
        stopping=Mock();stopping.wait.return_value=False
        with patch.object(module,'tunnel_healthy',return_value=False):
            module.monitor_tunnel(child,stopping)
        child.terminate.assert_called_once()
        child.wait.assert_called_once_with(timeout=5)
    def test_stopping_does_not_trigger_health_recovery(self):
        child=Mock();child.poll.return_value=None
        stopping=Mock();stopping.wait.return_value=True
        with patch.object(module,'tunnel_healthy') as health:
            module.monitor_tunnel(child,stopping)
        health.assert_not_called()
        child.terminate.assert_not_called()
    def test_only_local_context_and_loopback_proxy_are_forwarded(self):
        cmd=module.forward_command('colima')
        self.assertIn('8443:8443',cmd)
        self.assertIn('svc/ceerat-web-proxy',cmd)
        self.assertEqual(cmd[cmd.index('--address')+1],'localhost')
        self.assertNotIn('0.0.0.0',cmd)
        with self.assertRaises(ValueError):module.forward_command('production')
    def test_unrelated_process_is_never_treated_as_owned(self):
        with patch.object(module,'process_args',return_value=['python3','some-other-program.py']):
            self.assertFalse(module.owns_manager(123))
        with patch.object(module,'process_args',return_value=['python3',str(ROOT/'k8-scripts/forward.py'),'run','--context','colima']):
            self.assertTrue(module.owns_manager(123))
    def test_owned_orphan_requires_exact_proxy_command_and_context(self):
        with patch.object(module,'process_args',return_value=module.forward_command('colima')):
            self.assertTrue(module.owns_child(123,'colima'))
            self.assertFalse(module.owns_child(123,'docker-desktop'))
        with patch.object(module,'process_args',return_value=['sleep','30']):
            self.assertFalse(module.owns_child(123,'colima'))
    def test_legacy_shutdown_requires_known_service_and_mapping(self):
        self.assertTrue(module.legacy_owned(['kubectl','-n','ceerat-frontend','port-forward','svc/ceerat-customer-ui','3005:3005']))
        self.assertFalse(module.legacy_owned(['sleep','30']))
        self.assertFalse(module.legacy_owned(['kubectl','-n','other','port-forward','svc/other','3005:3005']))
if __name__=='__main__':unittest.main()
