"""End-to-end test of hecate-guest-enrollment against a disposable Authentik.

Never run it against live Hecate: it creates invitations and users. Start a
throwaway server and worker, import the `data` of netbird-blueprint.yaml and
guest-blueprint.yaml from /blueprints with `ak apply_blueprint`, then:

    docker cp scripts/hecate-guest-flow.test.py <server>:/tmp/test.py
    docker exec -w / <server> python /tmp/test.py

It creates invitations through `ak shell` and drives the flow executor API over
HTTP like a browser, completing MFA with a computed TOTP code.
"""

import base64
import hashlib
import hmac
import json
import struct
import subprocess
import sys
import time
import uuid
from urllib.parse import parse_qs, quote, urlparse

import requests

BASE = "http://localhost:9000"
SLUG = "hecate-guest-enrollment"
failures = []


def shell(code: str) -> str:
    out = subprocess.run(["ak", "shell", "-c", code], capture_output=True, text=True)
    lines = [l for l in out.stdout.splitlines() if l.startswith("RESULT ")]
    if not lines:
        raise RuntimeError(out.stdout[-2000:] + out.stderr[-2000:])
    return lines[-1][len("RESULT ") :]


def invite(fixed=None, expires_hours=None, single_use=False) -> str:
    exp = (
        f"now() + timedelta(hours={expires_hours})" if expires_hours is not None else "None"
    )
    return shell(
        f"""
from datetime import timedelta
from django.utils.timezone import now
from authentik.core.models import User
from authentik.flows.models import Flow
from authentik.stages.invitation.models import Invitation
i = Invitation.objects.create(name="guests-{uuid.uuid4().hex[:6]}", flow=Flow.objects.get(slug="{SLUG}"),
    created_by=User.objects.get(username="akadmin"), fixed_data={json.dumps(fixed or {})},
    expires={exp}, single_use={single_use})
print("RESULT", i.pk)
"""
    )


def user_state(username: str) -> dict:
    return json.loads(
        shell(
            f"""
import json
from authentik.core.models import User
u = User.objects.filter(username="{username}").first()
print("RESULT", json.dumps(None if not u else {{"active": u.is_active, "groups": sorted(g.name for g in u.groups.all()), "attrs": u.attributes, "path": u.path, "email": u.email}}))
"""
        )
    )


def totp(secret: str) -> str:
    key = base64.b32decode(secret + "=" * (-len(secret) % 8))
    digest = hmac.new(key, struct.pack(">Q", int(time.time()) // 30), hashlib.sha1).digest()
    o = digest[-1] & 15
    return f"{(struct.unpack('>I', digest[o:o + 4])[0] & 0x7FFFFFFF) % 1000000:06d}"


class Guest:
    def __init__(self, token: str):
        self.s = requests.Session()
        self.url = f"{BASE}/api/v3/flows/executor/{SLUG}/?query={quote('itoken=' + token)}"
        self.challenge = self.s.get(self.url).json()

    def post(self, body: dict) -> dict:
        self.challenge = self.s.post(self.url, json=body).json()
        return self.challenge

    def profile(self, username: str, email: str | None = None, password="correct-horse-battery"):
        return self.post(
            {
                "component": "ak-stage-prompt",
                "name": username.title(),
                "username": username,
                "email": email or f"{username}@example.test",
                "password": password,
                "password_repeat": password,
            }
        )

    def mfa(self) -> dict:
        c = self.challenge
        assert c["component"] == "ak-stage-authenticator-validate", c
        totp_stage = next(s for s in c["configuration_stages"] if "totp" in s["meta_model_name"])
        c = self.post({"component": c["component"], "selected_stage": totp_stage["pk"]})
        assert c["component"] == "ak-stage-authenticator-totp", c
        secret = parse_qs(urlparse(c["config_url"]).query)["secret"][0]
        return self.post({"component": c["component"], "code": totp(secret)})


def denied(c: dict) -> bool:
    return c["component"] == "ak-stage-access-denied"


def done(c: dict) -> bool:
    return c["component"] == "xak-flow-redirect"


def check(name: str, ok: bool, detail=None):
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f" :: {detail}"))
    if not ok:
        failures.append(name)


def message(c: dict) -> str:
    return json.dumps(c.get("error_message") or c.get("response_errors") or c.get("flow_info", ""))


def signup(token: str, username: str):
    g = Guest(token)
    if g.challenge["component"] != "ak-stage-prompt":
        return g.challenge
    g.profile(username)
    return g.mfa()


# 1. Use-limited link: two seats, third person refused.
t = invite({"max_uses": 2})
check("seat 1 signs up", done(signup(t, "guest-a")))
a = user_state("guest-a")
check(
    "seat 1 active guest, tagged",
    a["active"] and a["groups"] == ["guest"] and a["attrs"].get("guest_invitation") == t
    and a["path"] == "users/guests" and "max_uses" not in a["attrs"],
    a,
)
check("seat 2 signs up", done(signup(t, "guest-b")))
c = Guest(t).challenge
check("full link refused before the form", denied(c) and "no longer valid" in message(c), c)

# 2. Abandoned sign-up does not take a seat.
t = invite({"max_uses": 1})
g = Guest(t)
g.profile("guest-abandon")
check("abandoned account stays inactive", user_state("guest-abandon")["active"] is False)
check("abandoned sign-up leaves the seat free", done(signup(t, "guest-c")))
g = Guest(invite({"max_uses": 1}))
c = g.profile("guest-retry", email="guest-abandon@example.test")
check(
    "abandoned guest can retry with the same email",
    c["component"] == "ak-stage-authenticator-validate" and done(g.mfa()),
    c,
)

# 3. Filled during sign-up: the slower person is not activated.
t = invite({"max_uses": 1})
slow = Guest(t)
slow.profile("guest-slow")
check("fast person takes the last seat", done(signup(t, "guest-fast")))
c = slow.mfa()
check("slow person refused at activation", not done(c) and user_state("guest-slow")["active"] is False, c)

# 4. Revoked during sign-up.
t = invite({"max_uses": 5})
g = Guest(t)
g.profile("guest-revoked")
shell(f'from authentik.stages.invitation.models import Invitation; Invitation.objects.filter(pk="{t}").delete(); print("RESULT ok")')
c = g.mfa()
check("revoked link stops activation", not done(c) and user_state("guest-revoked")["active"] is False, c)

# 4b. Edited to an invalid limit during sign-up.
t = invite({"max_uses": 5})
g = Guest(t)
g.profile("guest-zeroed")
shell(f'from authentik.stages.invitation.models import Invitation; Invitation.objects.filter(pk="{t}").update(fixed_data={{"max_uses": 0}}); print("RESULT ok")')
c = g.mfa()
check("limit edited to 0 stops activation", not done(c) and user_state("guest-zeroed")["active"] is False, c)

# 5. Time-limited links.
check("time-only link works", done(signup(invite(expires_hours=24), "guest-time")))
check("time + uses link works", done(signup(invite({"max_uses": 3}, expires_hours=24), "guest-both")))
c = Guest(invite({"max_uses": 3}, expires_hours=-1)).challenge
check("expired link refused", denied(c), c)

# 6. Misconfigured and bogus links.
for name, tok in [
    ("single-use link refused", invite({"max_uses": 1}, single_use=True)),
    ("zero max_uses refused", invite({"max_uses": 0})),
    ("string max_uses refused", invite({"max_uses": "3"})),
    ("unknown token refused", str(uuid.uuid4())),
    ("malformed token refused", "not-a-uuid"),
]:
    c = Guest(tok).challenge
    check(name, denied(c), c)

# 7. Existing email cannot be claimed.
g = Guest(invite({"max_uses": 5}))
c = g.profile("guest-dupe", email="GUEST-A@example.test")
check("existing email rejected at the form", c["component"] == "ak-stage-prompt" and "already has an account" in json.dumps(c), c)
check("no account for duplicate email", user_state("guest-dupe") is None)

# 8. Mia's invitation flow tokens don't work here.
c = Guest(
    shell(
        """
from authentik.core.models import User
from authentik.stages.invitation.models import Invitation
i = Invitation.objects.create(name="other-flow", flow=None, created_by=User.objects.get(username="akadmin"), fixed_data={"max_uses": 5})
print("RESULT", i.pk)
"""
    )
).challenge
check("invitation without the guest flow refused", denied(c), c)

# 9. NetBird: guests pass the app binding and the claim carries only `guest`.
r = json.loads(
    shell(
        """
import json
from authentik.core.models import Application, User
from authentik.policies.engine import PolicyEngine
from authentik.providers.oauth2.models import ScopeMapping
u = User.objects.get(username="guest-a")
e = PolicyEngine(Application.objects.get(slug="netbird"), u); e.build()
m = ScopeMapping.objects.get(name="NetBird profile with permissions")
print("RESULT", json.dumps({"allowed": e.passing, "claim": m.evaluate(u, None)["groups"]}))
"""
    )
)
check("guest may sign in to NetBird with claim [guest]", r == {"allowed": True, "claim": ["guest"]}, r)

print(f"\n{len(failures)} failure(s)")
sys.exit(1 if failures else 0)
