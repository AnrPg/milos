defmodule Palee.Web.SeasonsControllerTest do
  @moduledoc """
  ADR-167 (P3-M5): a gym builds and sells a season; members ask for a place
  in `Box › Συνδρομή`; staff confirm (package, #season channel, programme) or
  decline; full seasons waitlist; the daily sweep completes and archives.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Finance, Notifications, Organizations, Repo, Seasons}
  alias Palee.Application.ListWorkoutExecutions
  alias Palee.Application.Seasons, as: SeasonsService
  alias Palee.Community.{Channel, Post}
  alias Palee.Workouts.{AssignedWorkout, AssignedWorkoutAthlete}

  import Ecto.Query

  setup %{conn: conn} do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Season Gym #{System.unique_integer([:positive])}"
      })

    person = fn role ->
      user = user_fixture()

      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })

      user
    end

    owner = person.(:owner)
    {:ok, owner_context} = Organizations.resolve_tenant_context(owner, organization.slug)
    workout = workout_fixture(owner, %{tenant_context: owner_context})

    {:ok, package} =
      Finance.create_package(owner_context, %{
        name: "Hyrox access",
        package_type: "class_pack",
        base_price_cents: 5000
      })

    %{
      organization: organization,
      slug: organization.slug,
      owner: owner,
      owner_context: owner_context,
      coach: person.(:coach),
      first: person.(:member),
      second: person.(:member),
      third: person.(:member),
      workout: workout,
      package: package,
      as: fn user -> put_bearer_token(conn, user) end,
      admin: "/api/org/#{organization.slug}/admin",
      me: "/api/org/#{organization.slug}/me"
    }
  end

  defp send_json(conn, method, path, body \\ %{}) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp drain, do: Oban.drain_queue(queue: :notifications, with_safety: false)
  defp types(user), do: Notifications.list_for_user(user.id) |> Enum.map(&to_string(&1.type))

  defp create_season!(ctx, attrs \\ %{}) do
    ctx.as.(ctx.owner)
    |> send_json(
      :post,
      "#{ctx.admin}/seasons",
      Map.merge(
        %{
          title: "Hyrox prep",
          description: "Οκτώ εβδομάδες για τον αγώνα.",
          welcome_message: "Καλώς ήρθατε! Ξεκινάμε τη Δευτέρα.",
          starts_on: Date.to_iso8601(Date.add(Date.utc_today(), 1)),
          weeks: 1,
          capacity: 1,
          price_cents: 9900,
          membership_package_id: ctx.package.id,
          programme: [
            %{day: 0, workout_id: ctx.workout.id},
            %{day: 2, workout_id: ctx.workout.id}
          ],
          coach_ids: [ctx.coach.id],
          status: "published"
        },
        attrs
      )
    )
    |> json_response(201)
    |> Map.fetch!("season")
  end

  defp execution(ctx, source, reference_id) do
    %{
      id: Ecto.UUID.generate(),
      organization_id: ctx.organization.id,
      master_workout_id: ctx.workout.id,
      source: source,
      source_reference_id: reference_id,
      section_scores: []
    }
  end

  defp enrollment_of(season, user),
    do: Enum.find(season["enrollments"], &(&1["user_id"] == user.id))

  defp season_assignments(season_id, user_id) do
    from(a in AssignedWorkout,
      join: l in AssignedWorkoutAthlete,
      on: l.assigned_workout_id == a.id,
      where: a.season_offering_id == ^season_id and l.athlete_id == ^user_id,
      select: l.scheduled_for,
      order_by: l.scheduled_for
    )
    |> Repo.all()
  end

  describe "the builder" do
    test "creates a draft or published season and validates its programme", ctx do
      season = create_season!(ctx, %{status: "draft"})

      assert %{
               "status" => "draft",
               "weeks" => 1,
               "workout_count" => 2,
               "places_left" => 1,
               "coaches" => [%{"id" => coach_id}],
               "enrollments" => []
             } = season

      assert coach_id == ctx.coach.id

      # The list names the staff the builder may pick as coaches.
      assert %{"seasons" => [_], "coach_candidates" => candidates} =
               ctx.as.(ctx.owner) |> get("#{ctx.admin}/seasons") |> json_response(200)

      assert Enum.any?(candidates, &(&1["id"] == ctx.coach.id))
      refute Enum.any?(candidates, &(&1["id"] == ctx.first.id))

      # A day outside the season is refused.
      assert ctx.as.(ctx.owner)
             |> send_json(:patch, "#{ctx.admin}/seasons/#{season["id"]}", %{
               programme: [%{day: 7, workout_id: ctx.workout.id}]
             })
             |> json_response(422)

      # A member is not a coach.
      assert %{"code" => "not_a_coach"} =
               ctx.as.(ctx.owner)
               |> send_json(:patch, "#{ctx.admin}/seasons/#{season["id"]}", %{
                 coach_ids: [ctx.first.id]
               })
               |> json_response(422)

      # Members don't see drafts and can't reach the builder.
      assert %{"seasons" => []} =
               ctx.as.(ctx.first) |> get("#{ctx.me}/seasons") |> json_response(200)

      assert ctx.as.(ctx.first) |> get("#{ctx.admin}/seasons") |> json_response(403)

      assert %{"status" => "published"} =
               ctx.as.(ctx.owner)
               |> send_json(:patch, "#{ctx.admin}/seasons/#{season["id"]}", %{status: "published"})
               |> json_response(200)
               |> Map.fetch!("season")
    end
  end

  describe "a place, from the request to the programme" do
    test "request, waitlist, confirm, full, remove, promote, decline", ctx do
      season = create_season!(ctx)
      id = season["id"]

      assert %{"seasons" => [%{"id" => ^id, "mine" => nil, "places_left" => 1}]} =
               ctx.as.(ctx.first) |> get("#{ctx.me}/seasons") |> json_response(200)

      assert %{"season" => %{"mine" => %{"status" => "requested"}, "places_left" => 0}} =
               ctx.as.(ctx.first)
               |> send_json(:post, "#{ctx.me}/seasons/#{id}/request")
               |> json_response(200)

      # Asking twice is refused.
      assert %{"code" => "season_already_requested"} =
               ctx.as.(ctx.first)
               |> send_json(:post, "#{ctx.me}/seasons/#{id}/request")
               |> json_response(409)

      # The only place is held: the second member waits.
      assert %{"season" => %{"mine" => %{"status" => "waitlisted"}}} =
               ctx.as.(ctx.second)
               |> send_json(:post, "#{ctx.me}/seasons/#{id}/request")
               |> json_response(200)

      drain()
      assert "season_requested" in types(ctx.owner)
      assert "season_requested" in types(ctx.coach)
      refute "season_requested" in types(ctx.first)

      detail = ctx.as.(ctx.owner) |> get("#{ctx.admin}/seasons/#{id}") |> json_response(200)
      first = enrollment_of(detail["season"], ctx.first)
      second = enrollment_of(detail["season"], ctx.second)

      confirmed =
        ctx.as.(ctx.owner)
        |> send_json(:post, "#{ctx.admin}/season-enrollments/#{first["id"]}/confirm")
        |> json_response(200)
        |> Map.fetch!("season")

      assert %{"status" => "active", "package_subscription_id" => subscription_id} =
               enrollment_of(confirmed, ctx.first)

      assert is_binary(subscription_id)
      assert confirmed["counts"] == %{"active" => 1, "requested" => 0, "waitlisted" => 1}

      # Finance: the package, at the season's price, for the season's dates.
      %{package_subscriptions: [subscription]} =
        Finance.get_member_profile(ctx.owner_context, ctx.first.id)

      assert subscription.id == subscription_id
      assert subscription.price_cents_snapshot == 9900
      assert subscription.ends_on == Date.add(Date.utc_today(), 7)

      # The programme: two workouts labelled with the season.
      starts = Date.add(Date.utc_today(), 1)
      assert season_assignments(id, ctx.first.id) == [starts, Date.add(starts, 2)]

      week =
        ctx.as.(ctx.first)
        |> get("/api/org/#{ctx.slug}/my-workouts?start_date=#{Date.to_iso8601(starts)}")
        |> json_response(200)

      assert [%{"season" => %{"id" => ^id, "title" => "Hyrox prep"}} = assignment | _] =
               week["assignments"]

      # Ημερολόγιο: an execution of a season workout carries the season too.
      assert [%{season: %{id: ^id, title: "Hyrox prep"}}, %{season: nil}] =
               ListWorkoutExecutions.summarize([
                 execution(ctx, :assigned, assignment["id"]),
                 execution(ctx, :self_selected, nil)
               ])

      # The #season channel: participants and staff see it; the welcome is pinned.
      channel = Repo.one!(from c in Channel, where: c.context_id == ^id, select: c)
      assert channel.kind == "season"
      assert confirmed["channel_id"] == channel.id

      assert [%Post{body: "Καλώς ήρθατε! Ξεκινάμε τη Δευτέρα.", pinned_at: %DateTime{}}] =
               Repo.all(from p in Post, where: p.channel_id == ^channel.id)

      channels = fn user ->
        ctx.as.(user)
        |> get("/api/me/clubs")
        |> json_response(200)
        |> Map.fetch!("clubs")
        |> Enum.flat_map(& &1["channels"])
        |> Enum.map(& &1["id"])
      end

      assert channel.id in channels.(ctx.first)
      assert channel.id in channels.(ctx.owner)
      refute channel.id in channels.(ctx.second)

      drain()
      assert "season_confirmed" in types(ctx.first)

      # No place left for the waitlisted member.
      assert %{"code" => "season_full"} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "#{ctx.admin}/season-enrollments/#{second["id"]}/confirm")
               |> json_response(409)

      # The schedule is fixed once someone is confirmed.
      assert %{"code" => "season_schedule_locked"} =
               ctx.as.(ctx.owner)
               |> send_json(:patch, "#{ctx.admin}/seasons/#{id}", %{weeks: 2})
               |> json_response(409)

      # A confirmed member settles a cancel with the box.
      assert %{"code" => "season_place_confirmed"} =
               ctx.as.(ctx.first)
               |> send_json(:post, "#{ctx.me}/seasons/#{id}/cancel")
               |> json_response(409)

      # Staff take the first member out: programme and channel go, the waitlist moves up.
      removed =
        ctx.as.(ctx.owner)
        |> send_json(:post, "#{ctx.admin}/season-enrollments/#{first["id"]}/remove")
        |> json_response(200)
        |> Map.fetch!("season")

      assert %{"status" => "cancelled"} = enrollment_of(removed, ctx.first)
      assert %{"status" => "requested"} = enrollment_of(removed, ctx.second)
      assert season_assignments(id, ctx.first.id) == []
      refute channel.id in channels.(ctx.first)

      declined =
        ctx.as.(ctx.owner)
        |> send_json(:post, "#{ctx.admin}/season-enrollments/#{second["id"]}/decline", %{
          reason: "Ξεκίνα με το επόμενο."
        })
        |> json_response(200)
        |> Map.fetch!("season")

      assert %{"status" => "declined", "decline_reason" => "Ξεκίνα με το επόμενο."} =
               enrollment_of(declined, ctx.second)

      drain()
      assert "season_declined" in types(ctx.second)

      # A declined member may ask again.
      assert %{"season" => %{"mine" => %{"status" => "requested"}}} =
               ctx.as.(ctx.second)
               |> send_json(:post, "#{ctx.me}/seasons/#{id}/request")
               |> json_response(200)
    end

    test "a member withdraws a request; cancelling the season tells everyone", ctx do
      season = create_season!(ctx, %{capacity: 3})
      id = season["id"]

      for user <- [ctx.first, ctx.second] do
        ctx.as.(user) |> send_json(:post, "#{ctx.me}/seasons/#{id}/request") |> json_response(200)
      end

      assert %{"season" => %{"mine" => %{"status" => "cancelled"}}} =
               ctx.as.(ctx.second)
               |> send_json(:post, "#{ctx.me}/seasons/#{id}/cancel")
               |> json_response(200)

      first =
        ctx.as.(ctx.owner)
        |> get("#{ctx.admin}/seasons/#{id}")
        |> json_response(200)
        |> Map.fetch!("season")
        |> enrollment_of(ctx.first)

      ctx.as.(ctx.owner)
      |> send_json(:post, "#{ctx.admin}/season-enrollments/#{first["id"]}/confirm")
      |> json_response(200)

      cancelled =
        ctx.as.(ctx.owner)
        |> send_json(:patch, "#{ctx.admin}/seasons/#{id}", %{status: "cancelled"})
        |> json_response(200)
        |> Map.fetch!("season")

      assert cancelled["status"] == "cancelled"
      assert %{"status" => "cancelled"} = enrollment_of(cancelled, ctx.first)
      assert season_assignments(id, ctx.first.id) == []

      channel = Repo.one!(from c in Channel, where: c.context_id == ^id, select: c)
      assert channel.archived_at

      drain()
      assert "season_cancelled" in types(ctx.first)
      refute "season_cancelled" in types(ctx.second)

      # A cancelled season the member held a place in is gone from the open list.
      assert %{"seasons" => []} =
               ctx.as.(ctx.third) |> get("#{ctx.me}/seasons") |> json_response(200)
    end
  end

  describe "the daily sweep" do
    test "completes an ended season and archives its channel", ctx do
      season = create_season!(ctx, %{capacity: 2})
      id = season["id"]

      ctx.as.(ctx.first)
      |> send_json(:post, "#{ctx.me}/seasons/#{id}/request")
      |> json_response(200)

      first =
        ctx.as.(ctx.owner)
        |> get("#{ctx.admin}/seasons/#{id}")
        |> json_response(200)
        |> Map.fetch!("season")
        |> enrollment_of(ctx.first)

      ctx.as.(ctx.owner)
      |> send_json(:post, "#{ctx.admin}/season-enrollments/#{first["id"]}/confirm")
      |> json_response(200)

      ctx.as.(ctx.second)
      |> send_json(:post, "#{ctx.me}/seasons/#{id}/request")
      |> json_response(200)

      # Move the season into the past.
      offering = Seasons.get_offering(ctx.owner_context, id)

      {:ok, _} =
        Seasons.update_offering(ctx.owner_context, offering, %{
          starts_on: Date.add(Date.utc_today(), -14),
          programme: []
        })

      assert :ok = SeasonsService.sweep(%{organization_id: ctx.organization.id})

      detail =
        ctx.as.(ctx.owner)
        |> get("#{ctx.admin}/seasons/#{id}")
        |> json_response(200)
        |> Map.fetch!("season")

      assert detail["status"] == "completed"
      assert %{"status" => "completed"} = enrollment_of(detail, ctx.first)
      assert %{"status" => "cancelled"} = enrollment_of(detail, ctx.second)

      channel = Repo.one!(from c in Channel, where: c.context_id == ^id, select: c)
      assert channel.archived_at

      # The member still sees the season they completed.
      assert %{"seasons" => [%{"id" => ^id, "mine" => %{"status" => "completed"}}]} =
               ctx.as.(ctx.first) |> get("#{ctx.me}/seasons") |> json_response(200)
    end
  end
end
