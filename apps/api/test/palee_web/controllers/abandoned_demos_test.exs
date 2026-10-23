defmodule PaleeWeb.AbandonedDemosTest do
  @moduledoc """
  ADR-184 follow-up: an idle demo business gets one reminder, is then wiped
  and archived, and comes back empty when its owner reopens it. As the RLS
  runtime role.
  """
  use PaleeWeb.ConnCase, async: false
  use Oban.Testing, repo: Palee.Repo

  import Ecto.Query
  import Palee.TestFixtures

  alias Oban.Testing
  alias Palee.Application.{AbandonedDemos, LoginUser}
  alias Palee.Notifications.Notification
  alias Palee.Workers.AbandonedDemosJob
  alias Palee.{BusinessAccounts, Identity, Organizations, Repo}

  @day 86_400

  setup %{conn: conn} do
    owner = user_fixture()
    %{conn: conn, owner: owner, as: fn user -> put_bearer_token(conn, user) end}
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
      business_name: "Box Παγκράτι #{System.unique_integer([:positive])}",
      timezone: "Europe/Athens"
    })
    |> json_response(201)
  end

  defp seed!(ctx, slug, section \\ "all") do
    ctx.as.(ctx.owner)
    |> send_json(:post, "/api/org/#{slug}/admin/business/demo-data", %{section: section})
    |> json_response(200)
  end

  defp lifecycle(organization_id) do
    %{rows: [[status, last_active_at, reminder_sent_at, archived_at]]} =
      Repo.query!(
        "SELECT status, demo_last_active_at, demo_reminder_sent_at, demo_archived_at " <>
          "FROM organizations WHERE id = $1",
        [Ecto.UUID.dump!(organization_id)]
      )

    %{
      status: status,
      last_active_at: utc(last_active_at),
      reminder_sent_at: utc(reminder_sent_at),
      archived_at: utc(archived_at)
    }
  end

  defp utc(nil), do: nil
  defp utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")

  defp idle!(organization_id, days, reminded_days_ago \\ nil) do
    now = DateTime.utc_now()

    Repo.query!(
      "UPDATE organizations SET demo_last_active_at = $2, demo_reminder_sent_at = $3 WHERE id = $1",
      [
        Ecto.UUID.dump!(organization_id),
        DateTime.add(now, -days * @day),
        reminded_days_ago && DateTime.add(now, -reminded_days_ago * @day)
      ]
    )
  end

  defp reminders(user_id) do
    Repo.all(
      from n in Notification,
        where: n.type == :business_demo_idle and n.user_id == ^user_id,
        select: n.payload
    )
  end

  defp demo_records(organization_id) do
    %{rows: [[count]]} =
      Repo.query!("SELECT count(*) FROM demo_records WHERE organization_id = $1", [
        Ecto.UUID.dump!(organization_id)
      ])

    count
  end

  defp mock_people(ctx, slug) do
    {:ok, context} = Organizations.resolve_tenant_context(ctx.owner, slug)

    for %{source: "users", record_id: id} <- BusinessAccounts.list_demo_records(context),
        do: id
  end

  defp sweep(now \\ DateTime.utc_now()) do
    Testing.with_testing_mode(:inline, fn -> AbandonedDemos.call(now) end)
  end

  describe "last activity" do
    test "signing up starts the clock; console requests and sign-ins keep it", ctx do
      %{"id" => org_id, "slug" => slug} = sign_up!(ctx)
      assert %{last_active_at: %DateTime{} = started, status: "active"} = lifecycle(org_id)

      # A request within the touch interval writes nothing.
      ctx.as.(ctx.owner) |> get("/api/org/#{slug}/admin/business") |> json_response(200)
      assert lifecycle(org_id).last_active_at == started

      # An older clock, or a claimed reminder, is reset by the next request.
      idle!(org_id, 61, 1)
      ctx.as.(ctx.owner) |> get("/api/org/#{slug}/admin/business") |> json_response(200)
      assert %{last_active_at: touched, reminder_sent_at: nil} = lifecycle(org_id)
      assert DateTime.diff(DateTime.utc_now(), touched) < 60

      # Signing in counts too.
      idle!(org_id, 61, 1)

      assert {:ok, _tokens} =
               LoginUser.call(%{identifier: ctx.owner.email, password: "S3cur3P@ss!42"})

      assert %{reminder_sent_at: nil, last_active_at: signed_in} = lifecycle(org_id)
      assert DateTime.diff(DateTime.utc_now(), signed_in) < 60
    end

    test "nobody but its owners and admins keeps a demo alive", ctx do
      %{"id" => org_id, "slug" => slug} = sign_up!(ctx)
      seed!(ctx, slug, "members")
      [mock_id | _] = mock_people(ctx, slug)
      idle!(org_id, 61)
      before = lifecycle(org_id).last_active_at

      assert BusinessAccounts.touch_demo_activity_on_sign_in(mock_id) == 0
      assert BusinessAccounts.touch_demo_activity_on_sign_in(user_fixture().id) == 0
      assert lifecycle(org_id).last_active_at == before
    end
  end

  describe "the sweep" do
    test "reminds once after 60 days, then archives after 90 without touching the owner",
         ctx do
      %{"id" => org_id, "slug" => slug} = sign_up!(ctx)
      seed!(ctx, slug)
      people = mock_people(ctx, slug)
      assert people != []
      assert demo_records(org_id) > 0

      # Not idle yet: nothing.
      idle!(org_id, 30)
      assert {:ok, %{reminded: 0, archived: 0}} = sweep()

      # 61 days: one reminder, claimed, never sent twice.
      idle!(org_id, 61)
      assert {:ok, %{reminded: 1, archived: 0}} = sweep()
      assert {:ok, %{reminded: 0, archived: 0}} = sweep()

      assert [payload] = reminders(ctx.owner.id)
      assert payload["organization_id"] == org_id
      assert payload["days_left"] in [30, "30"]
      assert %{reminder_sent_at: %DateTime{}} = lifecycle(org_id)

      # Mock people never hear from it.
      assert Enum.all?(people, &(reminders(&1) == []))

      # 91 days idle but the reminder only went out yesterday: still waiting.
      idle!(org_id, 91, 1)
      assert {:ok, %{archived: 0}} = sweep()

      # 91 days idle, 31 days after the reminder: archived and wiped.
      idle!(org_id, 91, 31)
      assert {:ok, %{reminded: 0, archived: 1}} = sweep()

      assert %{status: "archived", archived_at: %DateTime{}} = lifecycle(org_id)
      assert demo_records(org_id) == 0
      assert Enum.all?(people, &is_nil(Identity.find_by_id(&1)))

      # The owner's account and membership stay; the business leaves the session.
      assert %{} = Identity.find_by_id(ctx.owner.id)
      assert [:owner] == Organizations.member_roles(org_id, ctx.owner.id)

      memberships = ctx.as.(ctx.owner) |> get("/api/memberships") |> json_response(200)
      refute Enum.any?(memberships, &(&1["organization"]["id"] == org_id))

      # Its activation request is withdrawn.
      assert %{"requests" => [%{"kind" => "activation", "status" => "cancelled"}]} =
               ctx.as.(ctx.owner) |> get("/api/me/business-requests") |> json_response(200)

      # Sweeping again changes nothing.
      assert {:ok, %{reminded: 0, archived: 0}} = sweep()
    end

    test "owner activity after the reminder resets the clock and allows a new reminder later",
         ctx do
      %{"id" => org_id, "slug" => slug} = sign_up!(ctx)
      idle!(org_id, 61)
      assert {:ok, %{reminded: 1}} = sweep()

      ctx.as.(ctx.owner) |> get("/api/org/#{slug}/admin/business") |> json_response(200)
      assert %{reminder_sent_at: nil, status: "active"} = lifecycle(org_id)
      assert {:ok, %{reminded: 0, archived: 0}} = sweep()

      # A later idle spell gets its own reminder (a new dedupe key).
      idle!(org_id, 62)
      assert {:ok, %{reminded: 1}} = sweep()
      assert length(reminders(ctx.owner.id)) == 2
    end

    test "active businesses are never swept", ctx do
      %{"id" => org_id} = sign_up!(ctx)
      activate_business!(org_id)
      idle!(org_id, 200, 100)

      assert {:ok, %{reminded: 0, archived: 0}} = sweep()
      assert %{status: "active"} = lifecycle(org_id)
    end

    test "the daily job runs the sweep" do
      assert :ok = perform_job(AbandonedDemosJob, %{})
    end
  end

  describe "reopening" do
    setup ctx do
      %{"id" => org_id, "slug" => slug} = sign_up!(ctx)
      seed!(ctx, slug, "members")
      idle!(org_id, 91, 31)
      assert {:ok, %{archived: 1}} = sweep()
      Map.merge(ctx, %{org_id: org_id, slug: slug})
    end

    test "from Εγώ › Ρυθμίσεις: the demo comes back empty with a new activation request",
         ctx do
      assert %{"businesses" => [%{"id" => id, "provider_kind" => "gym"}]} =
               ctx.as.(ctx.owner) |> get("/api/me/archived-demos") |> json_response(200)

      assert id == ctx.org_id

      # Nobody else can reopen it.
      other = user_fixture()

      assert ctx.as.(other)
             |> send_json(:post, "/api/me/archived-demos/#{id}/reopen")
             |> json_response(404)

      assert %{
               "organization" => %{"id" => ^id, "activation" => "demo"},
               "request" => %{"kind" => "activation", "status" => "pending"}
             } =
               ctx.as.(ctx.owner)
               |> send_json(:post, "/api/me/archived-demos/#{id}/reopen")
               |> json_response(200)

      assert %{status: "active", archived_at: nil, reminder_sent_at: nil} = lifecycle(id)

      assert %{"gated" => true, "sections" => sections} =
               ctx.as.(ctx.owner)
               |> get("/api/org/#{ctx.slug}/admin/business")
               |> json_response(200)

      assert Enum.all?(sections, &(&1["seeded"] == false))

      assert %{"businesses" => []} =
               ctx.as.(ctx.owner) |> get("/api/me/archived-demos") |> json_response(200)

      # One demo at a time: it is live again.
      assert %{"code" => "business_account_exists"} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "/api/me/archived-demos/#{id}/reopen")
               |> json_response(409)
    end

    test "an account with another live demo cannot reopen the archived one", ctx do
      assert %{"id" => other_id} = sign_up!(ctx, "coach")
      refute other_id == ctx.org_id

      assert %{"code" => "business_account_exists"} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "/api/me/archived-demos/#{ctx.org_id}/reopen")
               |> json_response(409)

      assert %{status: "archived"} = lifecycle(ctx.org_id)
    end

    test "signing up again for the same kind reopens it", ctx do
      assert %{"id" => same, "activation" => "demo"} = sign_up!(ctx)
      assert same == ctx.org_id
      assert %{status: "active"} = lifecycle(same)
    end

    test "a conversion request for the same kind reopens it without a review", ctx do
      Repo.query!(
        "UPDATE users SET inserted_at = inserted_at - interval '2 days' WHERE id = $1",
        [
          Ecto.UUID.dump!(ctx.owner.id)
        ]
      )

      assert %{"kind" => "activation", "status" => "pending", "organization_id" => same} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "/api/me/business-requests", %{
                 business_kind: "gym",
                 business_name: "Box Παγκράτι ξανά"
               })
               |> json_response(201)

      assert same == ctx.org_id
      assert %{status: "active"} = lifecycle(same)
    end
  end
end
