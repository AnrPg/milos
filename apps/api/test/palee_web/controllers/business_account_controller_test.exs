defmodule PaleeWeb.BusinessAccountControllerTest do
  @moduledoc """
  ADR-184: a business opened at sign-up works in demo mode behind the
  go-live gate, fills its screens with demo data, and goes live through the
  activation link the platform team issues. Older accounts ask for a
  conversion. All as the RLS runtime role.
  """
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{BusinessAccounts, Identity, Notifications, Organizations}

  setup %{conn: conn} do
    owner = user_fixture()
    vendor = user_fixture()
    {:ok, _vendor} = Organizations.grant_vendor(vendor.id)

    %{
      conn: conn,
      owner: owner,
      vendor: vendor,
      as: fn user -> put_bearer_token(conn, user) end
    }
  end

  defp send_json(conn, method, path, body \\ %{}) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp sign_up!(ctx, kind \\ "gym") do
    ctx.as.(ctx.owner)
    |> send_json(:post, "/api/business-accounts", %{
      business_kind: kind,
      business_name: "Box Κυψέλη #{System.unique_integer([:positive])}",
      city: "Αθήνα",
      timezone: "Europe/Athens"
    })
    |> json_response(201)
  end

  defp age_account!(user) do
    Palee.Repo.query!(
      "UPDATE users SET inserted_at = inserted_at - interval '2 days' WHERE id = $1",
      [Ecto.UUID.dump!(user.id)]
    )
  end

  defp trial_ends_at(organization_id) do
    %{rows: [[ends_at]]} =
      Palee.Repo.query!(
        "SELECT trial_ends_at FROM organization_platform_subscriptions WHERE organization_id = $1",
        [Ecto.UUID.dump!(organization_id)]
      )

    ends_at
  end

  defp count(organization_id, table) do
    %{rows: [[count]]} =
      Palee.Repo.query!("SELECT count(*) FROM #{table} WHERE organization_id = $1", [
        Ecto.UUID.dump!(organization_id)
      ])

    count
  end

  describe "sign-up, demo mode and activation" do
    test "a demo gym is gated, fills its screens with demo data and goes live by the link",
         ctx do
      business = sign_up!(ctx)
      assert %{"activation" => "demo", "provider_kind" => "gym", "slug" => slug} = business
      org_id = business["id"]
      admin = "/api/org/#{slug}/admin/business"

      assert [:owner] == Organizations.member_roles(org_id, ctx.owner.id)

      assert memberships =
               ctx.as.(ctx.owner) |> get("/api/memberships") |> json_response(200)

      assert Enum.any?(memberships, &(&1["organization"]["activation"] == "demo"))

      assert %{
               "activation" => "demo",
               "gated" => true,
               "activation_request" => %{"kind" => "activation", "status" => "pending"},
               "sections" => sections
             } = ctx.as.(ctx.owner) |> get(admin) |> json_response(200)

      assert ~w(members schedule finance workouts) == Enum.map(sections, & &1["section"])

      # Going live is refused with the one stable error.
      assert %{"code" => "business_not_activated"} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "/api/org/#{slug}/invitations", %{role: "member"})
               |> json_response(403)

      # The floating button: the schedule needs the mock members first.
      assert %{"sections" => seeded} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "#{admin}/demo-data", %{section: "schedule"})
               |> json_response(200)

      by_section = Map.new(seeded, &{&1["section"], &1})
      assert %{"seeded" => true, "rows" => member_rows} = by_section["members"]
      assert member_rows > 0
      assert %{"seeded" => true} = by_section["schedule"]
      assert %{"seeded" => false} = by_section["finance"]

      assert %{"code" => "unknown_demo_section"} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "#{admin}/demo-data", %{section: "nope"})
               |> json_response(422)

      # Mock people cannot sign in and never get notifications.
      {:ok, owner_context} = Organizations.resolve_tenant_context(ctx.owner, slug)
      mock = Enum.find(BusinessAccounts.list_demo_records(owner_context), &(&1.source == "users"))
      mock_user = Identity.find_by_id(mock.record_id)
      assert mock_user.nickname =~ "_demo_"

      assert ctx.conn
             |> send_json(:post, "/api/auth/login", %{
               nickname: mock_user.nickname,
               password: "S3cur3P@ss!42"
             })
             |> json_response(401)

      assert BusinessAccounts.notification_suppressed?(org_id, mock_user.id)

      # A demo business notifies nobody outside its staff.
      outsider = user_fixture()

      assert :ok =
               Notifications.create_notification(%{
                 user_id: outsider.id,
                 organization_id: org_id,
                 type: "announcement",
                 title: "Hello",
                 body: "From a demo gym"
               })

      assert [] == Notifications.list_for_user(outsider.id)

      refute BusinessAccounts.notification_suppressed?(org_id, ctx.owner.id)

      # Only the platform team activates.
      assert ctx.as.(ctx.owner) |> get("/api/platform/business-accounts") |> json_response(403)

      assert %{"requests" => requests, "demo_businesses" => businesses} =
               ctx.as.(ctx.vendor) |> get("/api/platform/business-accounts") |> json_response(200)

      request = Enum.find(requests, &(&1["organization_id"] == org_id))
      assert %{"kind" => "activation", "status" => "pending"} = request
      assert Enum.any?(businesses, &(&1["organization"]["id"] == org_id))

      # The activation request stays open until the link is redeemed.
      assert %{
               "request" => %{"status" => "pending"},
               "activation_link" => %{"token" => token, "role" => "owner", "state" => "live"}
             } =
               ctx.as.(ctx.vendor)
               |> send_json(:post, "/api/platform/business-requests/#{request["id"]}/decision", %{
                 decision: "approve",
                 role: "owner"
               })
               |> json_response(200)

      # The link names one account.
      stranger = user_fixture()

      assert %{"code" => "invalid_activation_link"} =
               ctx.as.(stranger)
               |> send_json(:post, "/api/business-activation/inspect", %{token: token})
               |> json_response(404)

      assert %{"organization" => %{"id" => ^org_id}, "role" => "owner", "demo" => demo} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "/api/business-activation/inspect", %{token: token})
               |> json_response(200)

      assert demo["rows"] > 0 and demo["people"] > 0

      assert %{
               "organization" => %{"activation" => "active", "activated_at" => activated_at},
               "roles" => ["owner"],
               "removed" => %{"rows" => removed_rows, "people" => removed_people}
             } =
               ctx.as.(ctx.owner)
               |> send_json(:post, "/api/business-activation/redeem", %{token: token})
               |> json_response(200)

      assert activated_at
      assert removed_rows > 0 and removed_people > 0
      assert is_nil(Identity.find_by_id(mock_user.id))
      assert BusinessAccounts.list_demo_records(owner_context) == []

      assert %{"requests" => [%{"kind" => "activation", "status" => "completed"}]} =
               ctx.as.(ctx.owner) |> get("/api/me/business-requests") |> json_response(200)

      # Spent, and the gates are lifted.
      assert ctx.as.(ctx.owner)
             |> send_json(:post, "/api/business-activation/redeem", %{token: token})
             |> json_response(404)

      assert %{"activation" => "active", "gated" => false} =
               ctx.as.(ctx.owner) |> get(admin) |> json_response(200)

      assert %{"code" => "business_already_active"} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "#{admin}/demo-data", %{section: "members"})
               |> json_response(409)

      assert ctx.as.(ctx.owner)
             |> send_json(:post, "/api/org/#{slug}/invitations", %{role: "member"})
             |> json_response(201)
    end

    test "every section seeds and the remove button clears it all", ctx do
      %{"slug" => slug, "id" => org_id} = sign_up!(ctx, "coach")
      admin = "/api/org/#{slug}/admin/business"
      class_types_before = count(org_id, "class_types")

      assert %{"sections" => sections} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "#{admin}/demo-data", %{section: "all"})
               |> json_response(200)

      assert Enum.all?(sections, &(&1["seeded"] and &1["rows"] > 0))
      assert count(org_id, "membership_payments") > 0
      assert count(org_id, "bookings") > 0

      # Seeding again adds nothing: every section is already filled.
      assert %{"sections" => ^sections} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "#{admin}/demo-data", %{section: "all"})
               |> json_response(200)

      # Members never press the button.
      member = user_fixture()

      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: org_id,
          user_id: member.id,
          role: :member,
          status: :active,
          joined_at: DateTime.utc_now()
        })

      assert ctx.as.(member)
             |> send_json(:post, "#{admin}/demo-data", %{section: "all"})
             |> json_response(403)

      assert %{"sections" => cleared} =
               ctx.as.(ctx.owner)
               |> send_json(:delete, "#{admin}/demo-data")
               |> json_response(200)

      assert Enum.all?(cleared, &(not &1["seeded"]))
      assert count(org_id, "membership_payments") == 0
      assert count(org_id, "bookings") == 0
      # The owner's own configuration (the tenant defaults) stays.
      assert count(org_id, "class_types") == class_types_before
      assert [:owner, :coach] == Organizations.member_roles(org_id, ctx.owner.id)
    end

    test "a demo coach practice keeps the coach roles and an admin link adds admin", ctx do
      %{"id" => org_id, "provider_kind" => "coach"} = sign_up!(ctx, "coach")
      assert [:owner, :coach] == Organizations.member_roles(org_id, ctx.owner.id)

      assert %{"code" => "business_account_exists"} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "/api/business-accounts", %{
                 business_kind: "gym",
                 business_name: "Second"
               })
               |> json_response(409)

      partner = user_fixture()

      assert %{"code" => "account_not_found"} =
               ctx.as.(ctx.vendor)
               |> send_json(:post, "/api/platform/organizations/#{org_id}/activation-links", %{
                 role: "admin",
                 nickname: "nobody-#{System.unique_integer([:positive])}"
               })
               |> json_response(404)

      assert %{"token" => token, "id" => link_id} =
               ctx.as.(ctx.vendor)
               |> send_json(:post, "/api/platform/organizations/#{org_id}/activation-links", %{
                 role: "admin",
                 user_id: partner.id
               })
               |> json_response(201)

      assert %{"state" => "revoked"} =
               ctx.as.(ctx.vendor)
               |> send_json(:delete, "/api/platform/activation-links/#{link_id}")
               |> json_response(200)

      assert ctx.as.(partner)
             |> send_json(:post, "/api/business-activation/redeem", %{token: token})
             |> json_response(404)

      assert %{"token" => token} =
               ctx.as.(ctx.vendor)
               |> send_json(:post, "/api/platform/organizations/#{org_id}/activation-links", %{
                 role: "admin",
                 user_id: partner.id
               })
               |> json_response(201)

      # ADR-170: the trial counts from activation, not from the demo days.
      Palee.Repo.query!(
        "UPDATE organization_platform_subscriptions SET trial_ends_at = now() + interval '1 day' WHERE organization_id = $1",
        [Ecto.UUID.dump!(org_id)]
      )

      assert %{"roles" => ["admin", "coach"]} =
               ctx.as.(partner)
               |> send_json(:post, "/api/business-activation/redeem", %{token: token})
               |> json_response(200)

      assert NaiveDateTime.diff(trial_ends_at(org_id), NaiveDateTime.utc_now(), :day) >= 29
    end
  end

  describe "conversion requests" do
    test "an older account asks for a conversion; approving opens the demo business", ctx do
      age_account!(ctx.owner)
      requests = "/api/me/business-requests"
      body = %{business_kind: "coach", business_name: "Νίκος Παπαδόπουλος", phone: "6900000000"}

      assert %{"code" => "business_signup_closed"} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "/api/business-accounts", body)
               |> json_response(409)

      assert %{"id" => first, "status" => "pending", "kind" => "conversion"} =
               ctx.as.(ctx.owner) |> send_json(:post, requests, body) |> json_response(201)

      assert %{"code" => "business_request_pending"} =
               ctx.as.(ctx.owner) |> send_json(:post, requests, body) |> json_response(409)

      assert %{"status" => "cancelled"} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "#{requests}/#{first}/cancel")
               |> json_response(200)

      assert %{"id" => second} =
               ctx.as.(ctx.owner) |> send_json(:post, requests, body) |> json_response(201)

      # Nobody else sees or decides the request.
      assert %{"requests" => []} =
               ctx.as.(user_fixture()) |> get(requests) |> json_response(200)

      assert ctx.as.(ctx.owner)
             |> send_json(:post, "/api/platform/business-requests/#{second}/decision", %{
               decision: "approve"
             })
             |> json_response(403)

      assert %{
               "request" => %{"status" => "approved"},
               "organization" => %{"id" => org_id, "activation" => "demo"}
             } =
               ctx.as.(ctx.vendor)
               |> send_json(:post, "/api/platform/business-requests/#{second}/decision", %{
                 decision: "approve",
                 note: "Καλώς ήρθες"
               })
               |> json_response(200)

      assert [:owner, :coach] == Organizations.member_roles(org_id, ctx.owner.id)

      assert %{"code" => "business_request_closed"} =
               ctx.as.(ctx.vendor)
               |> send_json(:post, "/api/platform/business-requests/#{second}/decision", %{
                 decision: "decline"
               })
               |> json_response(409)

      assert %{"requests" => mine} = ctx.as.(ctx.owner) |> get(requests) |> json_response(200)
      kinds = Enum.map(mine, &{&1["kind"], &1["status"]})
      assert {"conversion", "approved"} in kinds
      assert {"activation", "pending"} in kinds
    end

    test "a declined request carries the note", ctx do
      age_account!(ctx.owner)

      assert %{"id" => id} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "/api/me/business-requests", %{
                 business_kind: "gym",
                 business_name: "CrossFit Test"
               })
               |> json_response(201)

      assert %{"request" => %{"status" => "declined", "decision_note" => "Need more details"}} =
               ctx.as.(ctx.vendor)
               |> send_json(:post, "/api/platform/business-requests/#{id}/decision", %{
                 decision: "decline",
                 note: "Need more details"
               })
               |> json_response(200)
    end
  end

  describe "discovery" do
    test "a demo business never shows on its public page", ctx do
      {:ok, organization} =
        Organizations.create_organization(%{
          name: "Live Gym #{System.unique_integer([:positive])}"
        })

      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: ctx.owner.id,
          role: :owner,
          status: :active,
          joined_at: DateTime.utc_now()
        })

      {:ok, context} = Organizations.resolve_tenant_context(ctx.owner, organization.slug)

      {:ok, profile} =
        Palee.Application.UpdateBoxPublicProfile.call(context, %{
          "about" => "Box",
          "disciplines" => ["crossfit"]
        })

      {:ok, _profile} =
        Palee.Application.PublishBoxPublicProfile.publish(context, %{
          "lock_version" => profile.lock_version
        })

      path = "/api/public/boxes/#{organization.slug}"
      assert ctx.conn |> get(path) |> json_response(200)

      Palee.Repo.query!("UPDATE organizations SET activation = 'demo' WHERE id = $1", [
        Ecto.UUID.dump!(organization.id)
      ])

      assert ctx.conn |> recycle() |> get(path) |> json_response(404)

      # Its own staff are told why; outsiders only see that it is unavailable.
      {:ok, context} = Organizations.resolve_tenant_context(ctx.owner, organization.slug)

      assert {:error, :business_not_activated} =
               Palee.Application.PublishBoxPublicProfile.publish(context, %{
                 "lock_version" => profile.lock_version + 1
               })
    end

    test "the organization's activation is only written by the platform", ctx do
      %{"id" => org_id} = sign_up!(ctx)

      assert_raise Postgrex.Error, ~r/decided by the platform team/, fn ->
        Palee.Repo.transaction(fn ->
          Palee.Repo.query!("SELECT set_config('app.user_id', $1, true)", [ctx.owner.id])

          Palee.Repo.query!("UPDATE organizations SET activation = 'active' WHERE id = $1", [
            Ecto.UUID.dump!(org_id)
          ])
        end)
      end
    end
  end
end
