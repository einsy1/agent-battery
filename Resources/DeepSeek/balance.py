"""Read balance metadata only; never call a model or print credentials."""
import json
import os
import subprocess
from decimal import Decimal, InvalidOperation
from urllib import request, error

ENDPOINT = 'https://api.deepseek.com/user/balance'


class NoRedirect(request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None  # Never forward the Authorization header to another endpoint.


def parse_balance(payload):
    if not isinstance(payload, dict) or type(payload.get('is_available')) is not bool:
        raise ValueError('invalid balance response')
    rows = payload.get('balance_infos')
    if not isinstance(rows, list) or not rows or len(rows) > 10:
        raise ValueError('missing balances')
    result = []
    seen = set()
    for row in rows:
        currency = row.get('currency')
        if currency not in ('CNY', 'USD') or currency in seen:
            raise ValueError('invalid currency')
        seen.add(currency)
        item = {'currency': currency}
        for field in ('total_balance', 'granted_balance', 'topped_up_balance'):
            raw = row.get(field)
            if not isinstance(raw, str) or not raw.strip() or len(raw) > 64:
                raise ValueError('invalid amount')
            value = Decimal(raw)
            if not value.is_finite() or abs(value) > Decimal('1e15') or value.as_tuple().exponent < -12:
                raise ValueError('invalid amount')
            item[field] = format(value, 'f')
        result.append(item)
    return {'status': 'ready', 'is_available': payload['is_available'], 'balances': result}


def fetch():
    try:
        saved = subprocess.run(['/usr/bin/security', 'find-generic-password', '-s',
                                'local.neil.codexbattery.deepseek', '-a', str(os.getuid()), '-w'],
                               capture_output=True, timeout=10)
        if saved.returncode == 44:
            return {'status': 'unconfigured', 'message': '配置 DeepSeek API Key 后查看余额'}
        if saved.returncode != 0:
            return {'status': 'error', 'message': '无法读取钥匙串，请允许访问后重试'}
        key = saved.stdout.decode().strip()
        if not key or '\n' in key or '\r' in key:
            return {'status': 'error', 'message': 'Key 无效，请重新配置'}
        req = request.Request(ENDPOINT, headers={'Authorization': 'Bearer ' + key, 'Accept': 'application/json'})
        opener = request.build_opener(NoRedirect())
        with opener.open(req, timeout=15) as response:
            data = response.read(65537)
            if len(data) > 65536:
                raise ValueError('response too large')
            return parse_balance(json.loads(data))
    except error.HTTPError as exc:
        if exc.code in (401, 403):
            message = 'Key 无效或无权限，请更新后重试'
        elif exc.code == 429:
            message = '查询暂时受限，请稍后重试'
        else:
            message = 'DeepSeek 余额服务暂不可用，请稍后重试'
        return {'status': 'error', 'message': message}
    except (ValueError, InvalidOperation, TypeError, AttributeError):
        return {'status': 'error', 'message': '余额数据格式不兼容，请稍后重试'}
    except Exception:
        return {'status': 'error', 'message': '余额查询失败，请检查网络和钥匙串权限后重试'}


if __name__ == '__main__':
    print(json.dumps(fetch(), ensure_ascii=False))
