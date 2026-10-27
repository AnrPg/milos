defmodule PaleeWeb.InvitationEmailsTest do
  @moduledoc """
  ADR-209: a box sends client and staff invitations by email: the send, the
  demo gate, delivery status, resend, bulk caps and the inbox binding.
  """
  use PaleeWeb.ConnCase, async: false
  use Palee.EmailCase

  import Ecto.Query
  import Palee.TestFixtures

  alias Palee.{Email, Identity, Organizations, Repo}
  alias Palee.Organizations.{Organization, OrganizationSetting, RegistrationInvitation}

  setup do
    owner = user_fixture(%{nickname: "Apostolos"})
    {:ok, organization} = Organizations.create_organization(%{name: "Box Kypseli"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    OrganizationSetting
    |> Repo.get_by!(organization_id: organization.id)
    |> OrganizationSetting.changeset(%{
      default_locale: "el",
      timezone: "Europe/Athens",
      brand_name: "Kypseli Box"
    })
    |> Repo.update!()

    on_exit(fn -> Application.delete_env(:palee, :invitation_email_limits) end)

    %{owner: owner, organization: organization, slug: organization.slug}
  end

  defp authed(conn, user),
    do: conn |> put_bearer_token(user) |> put_req_header("content-type", "application/json")

  defp send_invite(conn, ctx, body) do
    conn
    |> authed(ctx.owner)
    |> post("/api/org/#{ctx.slug}/invitations", Map.merge(%{"send_email" => true}, body))
  end

  defp token_from(message) do
    [_all, token] = Regex.run(~r{/invite#token=([A-Za-z0-9_\-%]+)}, message.text)
    URI.decode_www_form(token)
  end

  # The per-address throttle (2 minutes) would refuse an immediate resend.
  defp age_messages(minutes) do
    Repo.update_all(Email.Message,
      set: [inserted_at: DateTime.add(DateTime.utc_now(), -minutes * 60, :second)]
    )
  end

  describe "send by email" do
    test "emails the invitation in the box's language and never returns the token", ctx do
      conn =
        send_invite(ctx.conn, ctx, %{"role" => "member", "intended_email" => "Nikos@Example.com"})

      body = json_response(conn, 201)
      refute Map.has_key?(body, "token")
      assert %{"email" => "nikos@example.com", "delivery_status" => "queued", "id" => id} = body

      message =
        assert_email_enqueued(
          kind: :organization_invitation,
          to: "nikos@example.com",
          organization_id: ctx.organization.id,
          idempotency_key: "organization_invitation:#{id}"
        )

      assert message.locale == "el"
      assert message.category == "transactional"
      assert message.subject =~ "«Kypseli Box»"
      assert message.text =~ "Apostolos"
      assert message.text =~ "Μέλος box"
      assert message.html =~ "/invite#token="

      invitation = Repo.get!(RegistrationInvitation, id)
      assert invitation.emailed_at
      assert invitation.email_locale == "el"
      assert invitation.intended_email_encrypted == "nikos@example.com"

      # The stored column is ciphertext, never the address.
      [raw] =
        Repo.all(
          from i in "registration_invitations",
            where: i.id == type(^id, :binary_id),
            select: i.intended_email_encrypted
        )

      refute raw =~ "nikos"
    end

    test "a locale picked per invitation wins over the box's", ctx do
      conn =
        send_invite(ctx.conn, ctx, %{
          "role" => "athlete",
          "intended_email" => "maria@example.com",
          "email_locale" => "de"
        })

      assert json_response(conn, 201)
      message = assert_email_enqueued(kind: :organization_invitation, to: "maria@example.com")
      assert message.locale == "de"
      assert message.subject =~ "„Kypseli Box“"
    end

    test "a staff invitation lists the roles and branches", ctx do
      conn =
        send_invite(ctx.conn, ctx, %{
          "roles" => ["coach", "front_desk"],
          "intended_email" => "eleni@example.com",
          "email_locale" => "en"
        })

      assert json_response(conn, 201)
      message = assert_email_enqueued(kind: :organization_invitation, to: "eleni@example.com")
      assert message.text =~ "Coach, Front desk"
      assert message.text =~ "All branches"
    end

    test "an address is required and must be valid", ctx do
      conn = send_invite(ctx.conn, ctx, %{"role" => "member"})
      assert %{"code" => "invitation_email_required"} = json_response(conn, 422)

      conn = send_invite(recycle(conn), ctx, %{"role" => "member", "intended_email" => "nope"})
      assert %{"code" => "invalid_address"} = json_response(conn, 422)
      refute_email_enqueued(kind: :organization_invitation)
    end

    test "a suppressed address leaves no invitation behind", ctx do
      {:ok, _suppression} = Email.suppress("bounce@example.com", :bounce)

      conn =
        send_invite(ctx.conn, ctx, %{"role" => "member", "intended_email" => "bounce@example.com"})

      assert %{"code" => "suppressed"} = json_response(conn, 422)
      assert Repo.aggregate(RegistrationInvitation, :count) == 0
    end

    test "a box in demo mode cannot email invitations", ctx do
      Repo.update_all(where(Organization, id: ^ctx.organization.id), set: [activation: "demo"])

      conn =
        send_invite(ctx.conn, ctx, %{"role" => "member", "intended_email" => "x@example.com"})

      assert %{"code" => "business_not_activated"} = json_response(conn, 403)
      refute_email_enqueued(kind: :organization_invitation)
      assert Repo.aggregate(RegistrationInvitation, :count) == 0
    end

    test "copy links without send_email keep returning the token", ctx do
      conn =
        ctx.conn
        |> authed(ctx.owner)
        |> post("/api/org/#{ctx.slug}/invitations", %{"role" => "member"})

      assert %{"token" => token} = json_response(conn, 201)
      assert is_binary(token)
      refute_email_enqueued(kind: :organization_invitation)
    end
  end

  describe "delivery status and resend" do
    test "the pending list shows the address and the delivery status", ctx do
      send_invite(ctx.conn, ctx, %{"role" => "member", "intended_email" => "nikos@example.com"})

      list = fn ->
        ctx.conn
        |> authed(ctx.owner)
        |> get("/api/org/#{ctx.slug}/invitations")
        |> json_response(200)
      end

      assert [
               %{
                 "email" => "nikos@example.com",
                 "delivery_status" => "queued",
                 "email_bound" => true
               }
             ] =
               list.()

      assert deliver_enqueued_emails() == 1
      assert [%{"delivery_status" => "sent"}] = list.()

      # A later bounce suppresses the address; the sent invitation shows it.
      {:ok, _suppression} = Email.suppress("nikos@example.com", :bounce)
      assert [%{"delivery_status" => "bounced"}] = list.()
    end

    test "resend re-issues: the old link shows revoked, the new one works", ctx do
      %{"id" => old_id} =
        ctx.conn
        |> send_invite(ctx, %{"role" => "member", "intended_email" => "nikos@example.com"})
        |> json_response(201)

      old_token = token_from(assert_email_enqueued(kind: :organization_invitation))

      # Right away the throttle refuses it, and the old invitation stays.
      throttled =
        ctx.conn |> authed(ctx.owner) |> post("/api/org/#{ctx.slug}/invitations/#{old_id}/resend")

      assert %{"code" => "throttled"} = json_response(throttled, 429)
      assert is_nil(Repo.get!(RegistrationInvitation, old_id).revoked_at)

      age_messages(10)

      resent =
        ctx.conn |> authed(ctx.owner) |> post("/api/org/#{ctx.slug}/invitations/#{old_id}/resend")

      assert %{"id" => new_id, "email" => "nikos@example.com", "delivery_status" => "queued"} =
               json_response(resent, 201)

      assert new_id != old_id
      assert Repo.get!(RegistrationInvitation, old_id).revoked_at
      assert Repo.get!(RegistrationInvitation, new_id).email_locale == "el"

      new_message =
        assert_email_enqueued(idempotency_key: "organization_invitation:#{new_id}")

      inspect_token = fn token ->
        ctx.conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/invitations/inspect", %{invitation_token: token})
      end

      assert %{"code" => "invitation_revoked"} = json_response(inspect_token.(old_token), 410)

      assert %{"organization" => %{"name" => "Box Kypseli"}, "email_bound" => true} =
               json_response(inspect_token.(token_from(new_message)), 200)
    end

    test "only an emailed invitation can be resent", ctx do
      {:ok, tenant} = Organizations.resolve_tenant_context(ctx.owner, ctx.slug)
      {:ok, %{invitation: invitation}} = Organizations.issue_invitation(tenant, %{role: :member})

      conn =
        ctx.conn
        |> authed(ctx.owner)
        |> post("/api/org/#{ctx.slug}/invitations/#{invitation.id}/resend")

      assert %{"code" => "invitation_not_emailed"} = json_response(conn, 422)
    end
  end

  describe "bulk" do
    test "each address gets its own invitation and email; junk and repeats are skipped", ctx do
      conn =
        ctx.conn
        |> authed(ctx.owner)
        |> post("/api/org/#{ctx.slug}/invitations/bulk", %{
          "emails" =>
            "a@example.com, B@example.com; a@example.com\n\"c@example.com\" not-an-email",
          "role" => "member",
          "lifetime_seconds" => 86_400
        })

      assert %{"sent" => 3, "failed" => 0, "skipped" => ["not-an-email"], "results" => results} =
               json_response(conn, 201)

      assert Enum.map(results, & &1["email"]) == [
               "a@example.com",
               "b@example.com",
               "c@example.com"
             ]

      assert length(enqueued_emails(kind: :organization_invitation)) == 3
      assert Repo.aggregate(RegistrationInvitation, :count) == 3
    end

    test "a refused address is reported and the others still go", ctx do
      {:ok, _suppression} = Email.suppress("blocked@example.com", :complaint)

      conn =
        ctx.conn
        |> authed(ctx.owner)
        |> post("/api/org/#{ctx.slug}/invitations/bulk", %{
          "emails" => ["ok@example.com", "blocked@example.com"],
          "role" => "member"
        })

      assert %{"sent" => 1, "failed" => 1, "results" => results} = json_response(conn, 201)
      assert %{"email" => "blocked@example.com", "error" => "suppressed"} in results
    end

    test "more than 200 addresses are refused whole", ctx do
      emails = for n <- 1..201, do: "p#{n}@example.com"

      conn =
        ctx.conn
        |> authed(ctx.owner)
        |> post("/api/org/#{ctx.slug}/invitations/bulk", %{"emails" => emails, "role" => "member"})

      assert %{"code" => "too_many_invitation_emails"} = json_response(conn, 422)
      refute_email_enqueued(kind: :organization_invitation)
    end

    test "the box's daily cap refuses a list that would pass it, with telemetry", ctx do
      Application.put_env(:palee, :invitation_email_limits, per_organization_day: 3)
      ref = :telemetry_test.attach_event_handlers(self(), [[:palee, :invitations, :cap_reached]])

      first =
        ctx.conn
        |> authed(ctx.owner)
        |> post("/api/org/#{ctx.slug}/invitations/bulk", %{
          "emails" => ["a@example.com", "b@example.com"],
          "role" => "member"
        })

      assert %{"sent" => 2} = json_response(first, 201)

      second =
        ctx.conn
        |> authed(ctx.owner)
        |> post("/api/org/#{ctx.slug}/invitations/bulk", %{
          "emails" => ["c@example.com", "d@example.com"],
          "role" => "member"
        })

      assert %{"code" => "invitation_email_cap_reached"} = json_response(second, 429)
      assert_received {[:palee, :invitations, :cap_reached], ^ref, %{count: 1}, metadata}
      refute Map.has_key?(metadata, :email)
      assert length(enqueued_emails(kind: :organization_invitation)) == 2
      :telemetry.detach(ref)
    end
  end

  describe "binding: a verified address or the emailed link" do
    test "signing up through the emailed link verifies the new login", ctx do
      send_invite(ctx.conn, ctx, %{"role" => "member", "intended_email" => "new@example.com"})
      token = token_from(assert_email_enqueued(kind: :organization_invitation))

      conn =
        ctx.conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/register-member", %{
          handle: "new_person_#{System.unique_integer([:positive])}",
          display_name: "New Person",
          password: "S3cur3P@ss!42",
          email: "new@example.com",
          invitation_token: token
        })

      assert json_response(conn, 201)["access_token"]

      assert Identity.email_verified?(
               Identity.find_by_id(Identity.find_by_email("new@example.com").id)
             )
    end

    test "an existing unverified account with the address joins through the emailed link", ctx do
      invitee = user_fixture(%{email: "kostas@example.com"})
      refute Identity.email_verified?(invitee)

      send_invite(ctx.conn, ctx, %{"role" => "member", "intended_email" => "kostas@example.com"})
      token = token_from(assert_email_enqueued(kind: :organization_invitation))

      conn =
        ctx.conn |> authed(invitee) |> post("/api/memberships/redeem", %{invitation_token: token})

      assert json_response(conn, 201)["organization"]["slug"] == ctx.slug
      assert Identity.email_verified?(Identity.find_by_id(invitee.id))
    end

    test "signed in with another address: a clear message that never shows the invited one",
         ctx do
      other = user_fixture(%{email: "someone@example.com"})
      send_invite(ctx.conn, ctx, %{"role" => "member", "intended_email" => "secret@example.com"})
      token = token_from(assert_email_enqueued(kind: :organization_invitation))

      conn =
        ctx.conn |> authed(other) |> post("/api/memberships/redeem", %{invitation_token: token})

      body = json_response(conn, 403)
      assert body["code"] == "invitation_email_mismatch"
      refute inspect(body) =~ "secret"
      refute Identity.email_verified?(Identity.find_by_id(other.id))
    end

    test "a bound link that was not emailed needs a verified address", ctx do
      invitee = user_fixture(%{email: "copy@example.com"})

      %{"token" => token} =
        ctx.conn
        |> authed(ctx.owner)
        |> post("/api/org/#{ctx.slug}/invitations", %{
          "role" => "member",
          "intended_email" => "copy@example.com"
        })
        |> json_response(201)

      redeem = fn ->
        ctx.conn |> authed(invitee) |> post("/api/memberships/redeem", %{invitation_token: token})
      end

      assert %{"code" => "invitation_email_unverified"} = json_response(redeem.(), 403)

      :ok = Identity.mark_email_verified(invitee.login_id, "copy@example.com")
      assert json_response(redeem.(), 201)
    end
  end
end
