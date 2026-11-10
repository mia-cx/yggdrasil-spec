# Google sign-in test for sources-blueprint.yaml, against a disposable
# Authentik only: it creates a Google source, a linked identity and MFA devices.
#
#   docker cp scripts/hecate-google-sign-in.test.py <server>:/tmp/test.py
#   docker exec -e SETUP=1 <server> ak shell -c "exec(open('/tmp/test.py').read())"
#   # import sources.yaml from /blueprints with `ak apply_blueprint`, then:
#   docker exec <server> ak shell -c "exec(open('/tmp/test.py').read())"
#
# SETUP creates a Google source configured like live Hecate before the fix.
# The check drives the real OAuth source flow manager for a linked and an
# unknown Google identity, follows the resulting flow through the executor
# API, and exits non-zero on any failure. Run before the blueprint, it fails.
import os
import re
import sys

from django.contrib.auth.models import AnonymousUser
from django.test import Client, RequestFactory

from authentik.core.models import User
from authentik.flows.models import Flow
from authentik.root.middleware import SessionMiddleware
from authentik.sources.oauth.models import OAuthSource, UserOAuthSourceConnection
from authentik.sources.oauth.views.callback import OAuthSourceFlowManager
from authentik.stages.authenticator_totp.models import TOTPDevice

SECRET = "test-client-secret"
LINKED = "linked-sub"

if os.environ.get("SETUP"):
    source = OAuthSource.objects.create(
        name="Google", slug="google", provider_type="google",
        consumer_key="test-client-id", consumer_secret=SECRET,
        user_matching_mode="identifier",
        enrollment_flow=Flow.objects.get(slug="default-source-enrollment"),
        user_path_template="goauthentik.io/sources/%(slug)s",
    )
    UserOAuthSourceConnection.objects.create(
        user=User.objects.get(username="akadmin"), source=source, identifier=LINKED
    )
    print("RESULT set up")
    sys.exit(0)


def attempt(identifier: str) -> str:
    """Sign in as a Google identity; return where it ends up as one line."""
    client = Client()
    session = client.session
    request = RequestFactory().get("/source/oauth/callback/google/")
    request.session = session
    request.user = AnonymousUser()
    request.request_id = "test"
    response = OAuthSourceFlowManager(
        OAuthSource.objects.get(slug="google"), request, identifier,
        {"info": {"sub": identifier, "email": f"{identifier}@example.test", "name": identifier}},
        {},
    ).get_flow()
    session.save()
    client.cookies["authentik_session"] = SessionMiddleware.encode_session(
        session.session_key, AnonymousUser()
    )
    if response.status_code != 302:
        if hasattr(response, "render"):
            response.render()
        text = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", response.content.decode()))
        return "not configured for enrollment" if "not configured for enrollment" in text else text[:200]
    slug = response["Location"].strip("/").split("/")[-1]
    executor = client.get(f"/api/v3/flows/executor/{slug}/?query=")
    if executor.status_code == 302:
        client.get(executor["Location"])
        me = client.get("/api/v3/core/users/me/")
        return f"signed in as {me.json()['user']['username']}" if me.status_code == 200 else "not signed in"
    return f"{slug}: {executor.json()['component']}"


failures = []


def check(name: str, actual, expected):
    print(f"{'PASS' if actual == expected else 'FAIL'} {name}: {actual!r}")
    if actual != expected:
        failures.append(name)


source = OAuthSource.objects.get(slug="google")
admin = User.objects.get(username="akadmin")
users = User.objects.count()

check("enrollment flow cleared", source.enrollment_flow, None)
check("sign-in flow set", source.authentication_flow and source.authentication_flow.slug, "hecate-source-sign-in")
check(
    "source otherwise unchanged",
    (source.consumer_key, source.consumer_secret, source.user_matching_mode, source.enabled),
    ("test-client-id", SECRET, "identifier", True),
)
check(
    "linked identity kept",
    list(UserOAuthSourceConnection.objects.filter(source=source).values_list("user__username", "identifier")),
    [("akadmin", LINKED)],
)
check("unknown Google account refused", attempt("stranger-sub"), "not configured for enrollment")
check("no account created", User.objects.count() - users, 0)
check("linked account signs in", attempt(LINKED), "signed in as akadmin")
device = TOTPDevice.objects.create(user=admin, name="test", confirmed=True)
try:
    check("linked account with TOTP is asked for it", attempt(LINKED), "hecate-source-sign-in: ak-stage-authenticator-validate")
finally:
    device.delete()
direct = Client().get("/api/v3/flows/executor/hecate-source-sign-in/?query=")
check("flow refused when opened directly", direct.json().get("component") if direct["Content-Type"] == "application/json" else direct.status_code, "ak-stage-access-denied")

print(f"RESULT {len(failures)} failure(s)")
sys.exit(1 if failures else 0)
