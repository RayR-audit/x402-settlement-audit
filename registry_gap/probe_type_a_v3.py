# Type A probe v3 (public version): header (request=b64) AND body-JSON challenge
# paths, x402 v1+v2 shapes. Extracts ONLY payTo/recipient from accepts[] or
# top-level -- never currency contracts.
#
# Usage:
#   python probe_type_a_v3.py --hosts hosts.jsonl --registry base_facilitators.csv \
#       --out probe_results.csv [--rate 2] [--proxy http://127.0.0.1:7890]
#
# hosts.jsonl: one JSON object per line with at least {"resource": <url>, "host": <host>};
#   only lines with "state": "PAYABLE" are probed (same shape as the csoai
#   x402-bazaar-conformance snapshot). See README.md for details.
import urllib.request, urllib.error, json, base64, re, time, csv, os, argparse

KNOWN_CURRENCY = {
    '0x833589fcd6edb6e08f4c7c32d4f71b54bda02913',  # Base USDC
    '0x3c499c542cef5e3811e1192ce70d8cc03d5c3359',  # Polygon USDC (native)
    '0xaf88d065e77c8cc2239327c5edb3a432268e5831',  # Arbitrum USDC
}

def load_registry(path):
    return {r['address'].lower() for r in csv.DictReader(open(path, encoding='utf-8'))}

def extract_payees(obj):
    """Recursively find payTo/recipient values in challenge JSON (dict/list)."""
    out = []
    def walk(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if k in ('payTo', 'recipient', 'pay_to', 'payee') and isinstance(v, str) and re.match(r'^0x[a-fA-F0-9]{40}$', v):
                    out.append(v)
                else:
                    walk(v)
        elif isinstance(o, list):
            for x in o:
                walk(x)
    walk(obj)
    return [a for a in out if a.lower() not in KNOWN_CURRENCY]

def decode_request(www):
    m = re.search(r'request="([^"]+)"', www or '')
    if not m:
        return None
    b64 = m.group(1) + '=' * (-len(m.group(1)) % 4)
    try:
        return json.loads(base64.b64decode(b64))
    except Exception:
        return None

def probe(url, opener):
    try:
        opener.open(urllib.request.Request(url), timeout=15)
        return {'state': 'NO_402', 'method': '', 'payees': [], 'via': ''}
    except urllib.error.HTTPError as e:
        if e.code != 402:
            return {'state': 'HTTP_%d' % e.code, 'method': '', 'payees': [], 'via': ''}
        www = e.headers.get('WWW-Authenticate', '') or ''
        method = ''
        if 'method=' in www:
            try:
                method = www.split('method=')[1].split(',')[0].strip('"')
            except Exception:
                pass
        # path 1: header request= (x402 v1)
        j = decode_request(www)
        if j:
            return {'state': 'CHALLENGE', 'method': method, 'payees': extract_payees(j), 'via': 'header'}
        # path 2: body JSON (x402 v2)
        try:
            body = e.read().decode('utf-8', 'replace')
            j = json.loads(body)
            return {'state': 'CHALLENGE', 'method': method or 'x402v2', 'payees': extract_payees(j), 'via': 'body'}
        except Exception:
            return {'state': 'CHALLENGE', 'method': method, 'payees': [], 'via': 'unparsed'}
    except Exception:
        return {'state': 'ERR', 'method': '', 'payees': [], 'via': ''}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--hosts', required=True, help='host list JSONL (PAYABLE lines are probed)')
    ap.add_argument('--registry', required=True, help='facilitator registry CSV (address,facilitator)')
    ap.add_argument('--out', required=True, help='output CSV (resumable: already-probed hosts are skipped)')
    ap.add_argument('--rate', type=float, default=2.0, help='seconds between requests (be polite)')
    ap.add_argument('--proxy', default=os.environ.get('X402_PROBE_PROXY'), help='optional HTTP(S) proxy URL')
    args = ap.parse_args()

    handlers = []
    if args.proxy:
        handlers.append(urllib.request.ProxyHandler({'http': args.proxy, 'https': args.proxy}))
    opener = urllib.request.build_opener(*handlers)
    opener.addheaders = [('User-Agent', 'registry-gap-probe/3 (research; contact via repo issues)')]

    reg = load_registry(args.registry)
    done = set()
    if os.path.exists(args.out):
        done = {r['resource'] for r in csv.DictReader(open(args.out, encoding='utf-8'))}

    rows = [json.loads(l) for l in open(args.hosts, encoding='utf-8') if l.strip()]
    payable = [r for r in rows if r.get('state') == 'PAYABLE']
    newfile = not os.path.exists(args.out)
    with open(args.out, 'a', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        if newfile:
            w.writerow(['resource', 'host', 'probe_state', 'method', 'via', 'payees', 'payee_in_registry', 'gap_type'])
        for i, r in enumerate(payable):
            if r['resource'] in done:
                continue
            res = probe(r['resource'], opener)
            if res['state'] == 'CHALLENGE':
                if not res['payees']:
                    gap = 'no_payee'
                else:
                    inreg = any(p.lower() in reg for p in res['payees'])
                    gap = 'A_in' if inreg else 'A_out'
            else:
                gap = ''
            w.writerow([r['resource'], r['host'], res['state'], res['method'], res['via'], ';'.join(res['payees']),
                        '1' if gap == 'A_in' else ('0' if gap in ('A_out',) else ''), gap])
            f.flush()
            print('%d/%d %s %s %s' % (i + 1, len(payable), r['host'][:38], res['state'], gap))
            time.sleep(args.rate)

if __name__ == '__main__':
    main()
