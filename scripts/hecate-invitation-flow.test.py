"""Verify imported blueprints in disposable Authentik 2026.8.1, with SMTP mocked.

Run through `ak shell` after importing both invitation blueprints. The secret
guard refuses production. All database fixtures roll back after the checks.
"""

import base64
import os
from urllib.parse import parse_qs, urlencode, urlparse
from unittest.mock import patch
from uuid import uuid4

from django.conf import settings
from django.db import transaction
from django.test import Client
from django.urls import reverse

from authentik.core.models import AuthenticatedSession, Group, User
from authentik.flows.models import Flow
from authentik.lib.expression.evaluator import BaseEvaluator
from authentik.root.middleware import SessionMiddleware
from authentik.stages.authenticator.oath import TOTP
from authentik.stages.invitation.models import Invitation
from authentik.stages.prompt.models import PromptStage

assert os.environ.get("AUTHENTIK_SECRET_KEY") == "isolated-invitation-test-only"


def endpoint(slug, token=None):
    target = reverse("authentik_api:flow-executor", kwargs={"flow_slug": slug})
    return target + "?" + urlencode({"query": f"itoken={token}" if token else ""})


def finish(client, response):
    for _ in range(12):
        if response.status_code != 302:
            assert response.status_code == 200, response.content
            return response.json()
        response = client.get(response["Location"])
    raise AssertionError("Flow did not stop redirecting")


def post(client, target, **data):
    return finish(client, client.post(target, data, content_type="application/json"))


def signed_in(user):
    client = Client()
    session = client.session
    AuthenticatedSession.objects.create(session_id=session.session_key, user=user)
    client.cookies[settings.SESSION_COOKIE_NAME] = SessionMiddleware.encode_session(session.session_key, user)
    return client


def profile(client, invitation, **extra):
    target = endpoint("hecate-invitation-enrollment", invitation.pk)
    assert client.get(target).json()["component"] == "ak-stage-prompt"
    username = f"test-{uuid4()}"
    challenge = post(client, target, component="ak-stage-prompt", name="Invited Person",
                     username=username, password="testing-account-password",
                     password_repeat="testing-account-password", **extra)
    user = User.objects.get(username=username)
    assert challenge["component"] == "ak-stage-authenticator-validate", challenge
    assert not user.is_active and not user.groups.exists()
    return user, target, challenge


def complete_totp(client, target, challenge):
    selected = next(stage for stage in challenge["configuration_stages"]
                    if stage["name"] == "Authenticator app")
    setup = post(client, target, component="ak-stage-authenticator-validate",
                 selected_stage=selected["pk"])
    secret = parse_qs(urlparse(setup["config_url"]).query)["secret"][0]
    code = str(TOTP(base64.b32decode(secret)).token()).zfill(6)
    return post(client, target, component="ak-stage-authenticator-totp", code=code)


with transaction.atomic():
    form = PromptStage.objects.get(name="hecate-admin-invitation-form")
    names = [field.field_key.removeprefix("group:") for field in form.fields.all()
             if field.field_key.startswith("group:")]
    for name in names:
        Group.objects.get_or_create(name=name)
    admin_group = Group.objects.create(name=f"test-admin-{uuid4()}", is_superuser=True)
    admin = User.objects.create(username=f"test-admin-{uuid4()}")
    admin.groups.add(admin_group)
    ordinary = User.objects.create(username=f"test-person-{uuid4()}")
    admin_url = endpoint("hecate-admin-invite")
    client = signed_in(admin)

    with patch.object(BaseEvaluator, "expr_send_email", return_value=True) as email:
        before = Invitation.objects.count()
        challenge = client.get(admin_url).json()
        assert challenge["component"] == "ak-stage-prompt", challenge
        assert {field["field_key"] for field in challenge["fields"]} == {
            "email", *(f"group:{name}" for name in names)}
        assert Invitation.objects.count() == before and not email.called
        for actor in (None, ordinary):
            denied_client = signed_in(actor) if actor else Client()
            denied = finish(denied_client, denied_client.get(admin_url))
            assert denied["component"] != "ak-stage-prompt", denied
            denied_client.post(admin_url, {"component": "ak-stage-prompt",
                              "email": "unauthorized@example.invalid", "group:Nextcloud": True},
                              content_type="application/json")
        assert Invitation.objects.count() == before and not email.called
        print("PASS: only admins see the form; GETs and unauthorized POSTs send nothing")

        address = f"{uuid4()}@example.invalid"
        result = post(client, admin_url, component="ak-stage-prompt", email=address,
                      **{"group:Nextcloud": True, "group:Immich": True,
                         "group:authentik Admins": True})
        invitation = Invitation.objects.get(fixed_data__email=address)
        selected = {str(Group.objects.get(name=name).pk) for name in ("Nextcloud", "Immich")}
        assert set(invitation.fixed_data["groups"]) == selected
        assert invitation.single_use and invitation.created_by == admin
        assert result["component"] == "ak-stage-prompt", result
        assert "queued" in result["fields"][0]["initial_value"]
        assert email.call_count == 1 and email.call_args.kwargs["address"] == address
        assert email.call_args.kwargs["context"]["url"].startswith(
            "https://id.mia.cx/if/flow/hecate-invitation-enrollment/?itoken=")
        redirect = post(client, admin_url, component="ak-stage-prompt", email=address)
        assert redirect["final_redirect"] is True
        assert redirect["to"] == "/if/admin/#/flow/stages/invitations", redirect
        assert client.get(admin_url).json()["component"] == "ak-stage-prompt"
        assert email.call_count == 1
        print("PASS: selected groups bind to one invitation; forged admin selection and repeated POSTs add nothing")

    receiver = Client()
    user, target, challenge = profile(receiver, invitation,
                                     groups=[str(admin_group.pk)], **{"group:Pelican": True})
    complete_totp(receiver, target, challenge)
    user.refresh_from_db()
    assert user.is_active and set(user.groups.values_list("pk", flat=True)) == {
        Group.objects.get(name=name).pk for name in ("Nextcloud", "Immich")}
    assert not user.is_superuser
    print("PASS: no grants before MFA; selected groups apply after TOTP; recipient cannot add groups")

    # A deleted permission group must not activate a partially enrolled account.
    disappearing = Group.objects.create(name=f"test-deleted-{uuid4()}")
    interrupted = Invitation.objects.create(
        name=f"test-{uuid4()}", created_by=admin, single_use=True,
        flow=Flow.objects.get(slug="hecate-invitation-enrollment"),
        fixed_data={"email": f"{uuid4()}@example.invalid", "groups": [str(disappearing.pk)]})
    receiver = Client()
    user, target, challenge = profile(receiver, interrupted)
    disappearing.delete()
    complete_totp(receiver, target, challenge)
    user.refresh_from_db()
    assert not user.is_active and not user.groups.exists()
    print("PASS: group deletion during setup blocks activation")

    for invalid in ("Nextcloud", [123], ["not-a-uuid"], [str(uuid4())]):
        rejected = Invitation.objects.create(
            name=f"test-{uuid4()}", created_by=admin, single_use=True,
            flow=Flow.objects.get(slug="hecate-invitation-enrollment"),
            fixed_data={"email": f"{uuid4()}@example.invalid", "groups": invalid})
        denied = Client().get(endpoint("hecate-invitation-enrollment", rejected.pk)).json()
        assert denied["component"] == "ak-stage-access-denied"
        assert Invitation.objects.filter(pk=rejected.pk).exists()
    print("PASS: malformed or missing groups reject enrollment without consuming the invitation")

    client = signed_in(admin)
    client.get(admin_url)
    with patch.object(BaseEvaluator, "expr_send_email", return_value=False) as email:
        before = Invitation.objects.count()
        failed = post(client, admin_url, component="ak-stage-prompt",
                      email=f"{uuid4()}@example.invalid", **{"group:Nextcloud": True})
        assert failed["component"] == "ak-stage-prompt"
        assert Invitation.objects.count() == before and email.call_count == 1
        assert "queuing failed" in str(failed)
    with patch.object(BaseEvaluator, "expr_send_email", return_value=True) as email:
        existing = post(client, admin_url, component="ak-stage-prompt", email=user.email.upper())
        assert existing["component"] == "ak-stage-prompt" and not email.called
    print("PASS: queue failure rolls back invitation; existing email check ignores case")

    client = signed_in(admin)
    client.get(admin_url)
    admin.groups.remove(admin_group)
    with patch.object(BaseEvaluator, "expr_send_email", return_value=True) as email:
        before = Invitation.objects.count()
        post(client, admin_url, component="ak-stage-prompt", email=f"{uuid4()}@example.invalid")
        assert not email.called and Invitation.objects.count() == before
    print("PASS: losing admin rights after opening the form blocks submission")
    transaction.set_rollback(True)

print("PASS: admin invitation checks complete; fixtures rolled back; no SMTP delivery")
