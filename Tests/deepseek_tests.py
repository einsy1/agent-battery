import importlib.util
import io
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch, Mock
from urllib.error import HTTPError, URLError

spec = importlib.util.spec_from_file_location('balance', Path(__file__).parents[1]/'Resources/DeepSeek/balance.py')
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)


def payload(value='0.00'):
    return {'is_available': False, 'balance_infos': [{'currency': 'CNY', 'total_balance': value,
            'granted_balance': '0.00', 'topped_up_balance': value}]}


class BalanceTests(unittest.TestCase):
    def test_zero_and_decimal_precision(self):
        row = b.parse_balance(payload())
        self.assertEqual(row['status'], 'ready')
        self.assertEqual(row['balances'][0]['total_balance'], '0.00')
        self.assertFalse(row['is_available'])
        self.assertEqual(b.parse_balance(payload('1.234567'))['balances'][0]['total_balance'], '1.234567')

    def test_invalid_and_missing_data(self):
        for value in ['NaN', 'Infinity', '', 'abc', '1e1000']:
            with self.assertRaises((ValueError, b.InvalidOperation)):
                b.parse_balance(payload(value))
        for value in [{}, {'is_available': True, 'balance_infos': []}, {'is_available': 1, 'balance_infos': []}]:
            with self.assertRaises(ValueError): b.parse_balance(value)

    def test_currency_kept_separate(self):
        value = payload('1.00')
        usd = dict(value['balance_infos'][0], currency='USD', total_balance='2.00')
        value['balance_infos'].append(usd)
        self.assertEqual([x['currency'] for x in b.parse_balance(value)['balances']], ['CNY', 'USD'])
        value['balance_infos'].append(usd)
        with self.assertRaises(ValueError): b.parse_balance(value)

    def test_unconfigured_never_contacts_network(self):
        with patch.object(b.subprocess, 'run', return_value=Mock(returncode=44)), patch.object(b.request, 'build_opener') as network:
            self.assertEqual(b.fetch()['status'], 'unconfigured')
            network.assert_not_called()

    def test_real_request_shape_and_no_secret_output(self):
        secret = 'test-credential-not-a-real-key'
        response = Mock()
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        response.read.return_value = json.dumps(payload('12.34')).encode()
        opener = Mock()
        opener.open.return_value = response
        with patch.object(b.subprocess, 'run', return_value=Mock(returncode=0, stdout=secret.encode())), patch.object(b.request, 'build_opener', return_value=opener):
            result = b.fetch()
            req = opener.open.call_args.args[0]
            self.assertEqual(req.full_url, b.ENDPOINT)
            self.assertEqual(req.get_method(), 'GET')
            self.assertEqual(req.get_header('Authorization'), 'Bearer ' + secret)
            self.assertNotIn(secret, json.dumps(result))
            self.assertEqual(result['status'], 'ready')
        self.assertIsNone(b.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://example.com'))

    def test_errors_never_leak_response_or_stale_amount(self):
        for exc in [HTTPError(b.ENDPOINT, 401, 'private error', {}, None), HTTPError(b.ENDPOINT, 429, '', {}, None), URLError('private error')]:
            with patch.object(b.subprocess, 'run', return_value=Mock(returncode=0, stdout=b'test-key')), patch.object(b.request, 'build_opener') as opener:
                opener.return_value.open.side_effect = exc
                result = b.fetch()
                self.assertEqual(result['status'], 'error')
                self.assertNotIn('private', json.dumps(result))
                self.assertNotIn('balances', result)
        with patch.object(b.subprocess, 'run', side_effect=subprocess.TimeoutExpired('security', 10)):
            self.assertEqual(b.fetch()['status'], 'error')


if __name__ == '__main__': unittest.main()
