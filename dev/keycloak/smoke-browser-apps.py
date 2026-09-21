#!/usr/bin/env python3
"""Redacted local browser-app policy smoke test; never prints cookies, codes, or tokens."""

import json
import urllib.error
import urllib.parse
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


OPENER = urllib.request.build_opener(NoRedirect)


def request(url, method="GET", data=None):
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method=method)
    try:
        with OPENER.open(req, timeout=5) as response:
            return response.status, response.headers
    except urllib.error.HTTPError as error:
        return error.code, error.headers


def check_oauth(base, client_id):
    results = []
    for path in ("/oauth/login", "/oauth/register", "/oauth/google"):
        status, headers = request(base + path)
        assert status == 303, (path, status)
        location = headers["Location"]
        query = urllib.parse.parse_qs(urllib.parse.urlparse(location).query)
        assert query.get("client_id") == [client_id]
        assert query.get("code_challenge_method") == ["S256"]
        assert "state" in query and "code_challenge" in query
        if path == "/oauth/register":
            assert "/registrations" in location
        if path == "/oauth/google":
            assert query.get("kc_idp_hint") == ["google"]
        results.append({"surface": base + path, "result": "policy_ok"})
    return results


def main():
    results = check_oauth("http://localhost:3000", "ceerat-web-ui")
    results += check_oauth("http://localhost:3005", "ceerat-customer-ui")
    checks = (
        ("http://localhost:8088/healthz", "GET", None, 200),
        ("http://localhost:8088/agent/chat", "POST", b"{}", 401),
        ("http://localhost:8088/customer/chat", "POST", b"{}", 404),
        ("http://localhost:3005/api/agent/chat", "POST", b"{}", 405),
        ("http://localhost:3005/api/customers", "POST", b"{}", 405),
        ("http://localhost:3000/agent/chat", "GET", None, 303),
    )
    for url, method, body, expected in checks:
        status, _ = request(url, method, body)
        assert status == expected, (url, status, expected)
        results.append({"surface": url, "result": "blocked" if status in (401, 403, 404, 405) else "ok"})
    print(json.dumps({"ok": True, "checks": results}, indent=2))


if __name__ == "__main__":
    main()
