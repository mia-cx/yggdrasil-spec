# Google sign-in check for sources-blueprint.yaml, against a disposable
# Authentik only: it creates a Google source, a linked identity and MFA devices.
#
#   docker cp scripts/hecate-google-sign-in.test.py <server>:/tmp/test.py
#   docker exec -e SETUP=1 <server> ak shell -c "exec(open('/tmp/test.py').read())"
#   # import sources.yaml from /blueprints with `ak apply_blueprint`, then rerun without SETUP
#
# Drives the real OAuth source flow manager for a linked and an unknown Google
# identity, follows the resulting flow through the executor API, and prints one
# RESULT line. After the blueprint: unknown is refused, linked signs in, a
# linked account with TOTP is asked for it, and the flow can't be opened directly.
import json
import os

from django.contrib.auth.models import AnonymousUser
from django.test import Client, RequestFactory

from authentik.core.models import User, UserSourceConnection
from authentik.flows.models import Flow
from authentik.sources.oauth.models import OAuthSource, UserOAuthSourceConnection
from authentik.sources.oauth.views.callback import OAuthSourceFlowManager
from authentik.stages.authenticator_totp.models import TOTPDevice

if os.environ.get("SETUP"):
    source = OAuthSource.objects.create(
        name="Google", slug="google", provider_type="google",
        consumer_key="test-client-id", consumer_secret="test-client-secret",
        user_matching_mode="identifier",
        enrollment_flow=Flow.objects.get(slug="default-source-enrollment"),
        user_path_template="goauthentik.io/sources/%(slug)s",
    )
    UserOAuthSourceConnection.objects.create(
        user=User.objects.get(username="akadmin"), source=source, identifier="linked-sub"
    )


def attempt(identifier: str) -> str:
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
    from authentik.root.middleware import SessionMiddleware

    client.cookies["authentik_session"] = SessionMiddleware.encode_session(
        session.session_key, AnonymousUser()
    )
    if hasattr(response, "render"):
        response.render()
    body = getattr(response, "content", b"").decode(errors="replace")
    if response.status_code != 302:
        return f"{response.status_code}: " + (
            "not configured for enrollment" if "not configured for enrollment" in body
            else "configured flow does not exist" if "Configured flow does not exist" in body
            else body[:120]
        )
    slug = response["Location"].strip("/").split("/")[-1]
    executor = client.get(f"/api/v3/flows/executor/{slug}/?query=")
    if executor.status_code == 302:
        followed = client.get(executor["Location"])
        me = client.get("/api/v3/core/users/me/")
        signed_in = me.status_code == 200 and me.json()["user"]["username"]
        component = followed.json()["component"] if followed["Content-Type"] == "application/json" else followed.status_code
        return f"{slug}: 302 {executor['Location']} -> {component}, signed in as {signed_in}"
    if executor["Content-Type"] != "application/json":
        import re
        text = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", executor.content.decode()))
        return f"{slug}: HTTP {executor.status_code} {text[:400]}"
    challenge = executor.json()
    return f"{slug}: {challenge['component']}"


source = OAuthSource.objects.get(slug="google")
admin = User.objects.get(username="akadmin")
result = {
    "fields": {
        "name": source.name, "enabled": source.enabled, "consumer_key": source.consumer_key,
        "secret_set": bool(source.consumer_secret), "user_matching_mode": source.user_matching_mode,
        "enrollment_flow": source.enrollment_flow and source.enrollment_flow.slug,
        "authentication_flow": source.authentication_flow and source.authentication_flow.slug,
        "path": source.user_path_template,
    },
    "connections": UserSourceConnection.objects.filter(source=source).count(),
    "unknown": attempt("stranger-sub"),
    "linked_no_mfa": attempt("linked-sub"),
}
device = TOTPDevice.objects.create(user=admin, name="test", confirmed=True)
result["linked_with_totp"] = attempt("linked-sub")
device.delete()
users_before = User.objects.count()
if Flow.objects.filter(slug="hecate-source-sign-in").exists():
    result["flow_opened_directly"] = Client().get(
        "/api/v3/flows/executor/hecate-source-sign-in/?query="
    ).json()["component"]
result["users_created_by_unknown"] = (attempt("stranger-sub"), User.objects.count() - users_before)[1]
print("RESULT", json.dumps(result))
