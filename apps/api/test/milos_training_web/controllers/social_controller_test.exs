defmodule MilosTraining.Web.SocialControllerTest do
  @moduledoc """
  ADR-142 (P2-M2): the public box page, follows of people and boxes, profile
  posts with their audiences, staff-only public club posts and the feed that
  merges them.
  """

  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.{Notifications, Organizations}
  alias MilosTraining.Application.{PublishBoxPublicProfile, UpdateBoxPublicProfile}

  setup %{conn: conn} do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:milos_training, Oban), :testing, :manual)}
    )

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Social Gym #{System.unique_integer([:positive])}"
      })

    person = fn role ->
      user = user_fixture()

      if role do
        {:ok, _membership} =
          Organizations.add_membership(%{
            organization_id: organization.id,
            user_id: user.id,
            role: role,
            status: :active,
            joined_at: DateTime.utc_now()
          })
      end

      user
    end

    owner = person.(:owner)
    {:ok, owner_context} = Organizations.resolve_tenant_context(owner, organization.slug)

    %{
      organization: organization,
      owner: owner,
      owner_context: owner_context,
      coach: person.(:coach),
      member: person.(:member),
      outsider: person.(nil),
      stranger: person.(nil),
      anonymous: conn,
      as: fn user -> put_bearer_token(conn, user) end,
      base: "/api/org/#{organization.slug}/community"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp publish!(ctx, attrs \\ %{}) do
    {:ok, profile} =
      UpdateBoxPublicProfile.call(
        ctx.owner_context,
        Map.merge(%{"about" => "Ένα box στην Κυψέλη.", "disciplines" => ["crossfit"]}, attrs)
      )

    {:ok, profile} =
      PublishBoxPublicProfile.publish(ctx.owner_context, %{
        "lock_version" => profile.lock_version
      })

    profile
  end

  defp notifications(user), do: Notifications.list_for_user(user.id) |> Enum.map(& &1.type)

  defp drain, do: Oban.drain_queue(queue: :notifications, with_safety: false)

  describe "public box page" do
    test "only a published gym resolves, by slug or alias, and shows the published snapshot",
         ctx do
      slug = ctx.organization.slug
      assert ctx.anonymous |> get("/api/public/boxes/#{slug}") |> json_response(404)

      publish!(ctx, %{"coach_ids" => [ctx.coach.id]})

      assert %{
               "box" => %{"slug" => ^slug},
               "profile" => %{
                 "about" => "Ένα box στην Κυψέλη.",
                 "languages" => ["el", "en"],
                 "coaches" => [%{"id" => coach_id, "class_types" => []}]
               },
               "followers_count" => 0
             } = ctx.anonymous |> get("/api/public/boxes/#{slug}") |> json_response(200)

      assert coach_id == ctx.coach.id

      # A draft edit stays off the page until published.
      {:ok, _draft} = UpdateBoxPublicProfile.call(ctx.owner_context, %{"about" => "Draft"})

      assert %{"profile" => %{"about" => "Ένα box στην Κυψέλη."}} =
               ctx.anonymous |> get("/api/public/boxes/#{slug}") |> json_response(200)

      vendor = user_fixture()
      {:ok, _vendor} = Organizations.grant_vendor(vendor.id)
      {:ok, platform} = Organizations.resolve_platform_context(vendor)
      new_slug = "social-renamed-#{System.unique_integer([:positive])}"

      {:ok, _renamed} =
        Organizations.rename_organization_slug(platform, ctx.organization.id, %{
          "slug" => new_slug,
          "confirmation" => slug
        })

      assert %{"box" => %{"slug" => ^new_slug}} =
               ctx.anonymous |> get("/api/public/boxes/#{slug}") |> json_response(200)

      {:ok, _profile} = PublishBoxPublicProfile.unpublish(ctx.owner_context)
      assert ctx.anonymous |> get("/api/public/boxes/#{new_slug}") |> json_response(404)
    end

    test "schedule and posts need sign-in (board 4 D2)", ctx do
      publish!(ctx)
      slug = ctx.organization.slug

      assert ctx.anonymous |> get("/api/public/boxes/#{slug}/schedule") |> response(404)
      assert ctx.anonymous |> get("/api/boxes/#{slug}/schedule") |> response(401)
      assert ctx.anonymous |> get("/api/boxes/#{slug}/posts") |> response(401)

      assert %{"slots" => [], "box" => %{"slug" => ^slug}} =
               ctx.as.(ctx.outsider) |> get("/api/boxes/#{slug}/schedule") |> json_response(200)

      assert ctx.as.(ctx.outsider)
             |> get(
               "/api/boxes/#{slug}/schedule?start_at=2026-01-01T00:00:00Z&end_at=2026-03-01T00:00:00Z"
             )
             |> response(400)
    end

    test "coaches must be the gym's staff", ctx do
      assert {:error, :invalid_public_profile} =
               UpdateBoxPublicProfile.call(ctx.owner_context, %{"coach_ids" => [ctx.member.id]})

      assert {:ok, %{coaches: [%{id: id}], coach_candidates: candidates}} =
               UpdateBoxPublicProfile.call(ctx.owner_context, %{"coach_ids" => [ctx.coach.id]})

      assert id == ctx.coach.id
      assert ctx.owner.id in Enum.map(candidates, & &1.id)
      refute ctx.member.id in Enum.map(candidates, & &1.id)
    end
  end

  describe "box audiences and follows" do
    test "only staff post publicly; followers outside the gym see public posts only", ctx do
      %{as: as, base: base} = ctx
      publish!(ctx)

      assert %{"clubs" => [club]} = as.(ctx.member) |> get("/api/me/clubs") |> json_response(200)
      wod = Enum.find(club["channels"], &(&1["kind"] == "wod"))
      announcements = Enum.find(club["channels"], &(&1["kind"] == "announcements"))

      assert %{"code" => "invalid_audience"} =
               as.(ctx.member)
               |> send_json(:post, "#{base}/posts", %{
                 channel_id: wod["id"],
                 audience: "public",
                 body: "Hi world"
               })
               |> json_response(422)

      assert %{"post" => %{"id" => public_id, "audience" => "public"}} =
               as.(ctx.coach)
               |> send_json(:post, "#{base}/posts", %{
                 channel_id: announcements["id"],
                 audience: "public",
                 body: "Open day on Saturday"
               })
               |> json_response(201)

      assert %{"post" => %{"id" => club_only_id}} =
               as.(ctx.coach)
               |> send_json(:post, "#{base}/posts", %{
                 channel_id: announcements["id"],
                 body: "Members: towels are back"
               })
               |> json_response(201)

      assert %{"status" => "active"} =
               as.(ctx.outsider)
               |> send_json(:post, "/api/me/follows", %{
                 target_type: "organization",
                 target_id: ctx.organization.id
               })
               |> json_response(200)

      assert %{"posts" => [%{"id" => ^public_id, "origin" => "club", "channel" => nil}]} =
               as.(ctx.outsider) |> get("/api/me/feed") |> json_response(200)

      assert %{"posts" => [%{"id" => ^public_id}]} =
               as.(ctx.outsider)
               |> get("/api/boxes/#{ctx.organization.slug}/posts")
               |> json_response(200)

      # A member sees each post once, through their club.
      assert %{"posts" => posts} = as.(ctx.member) |> get("/api/me/feed") |> json_response(200)
      assert Enum.sort(Enum.map(posts, & &1["id"])) == Enum.sort([public_id, club_only_id])

      assert %{"followers_count" => 1} =
               ctx.anonymous
               |> get("/api/public/boxes/#{ctx.organization.slug}")
               |> json_response(200)

      assert %{"entries" => [%{"box" => %{"organization_id" => org_id}}]} =
               as.(ctx.outsider)
               |> get("/api/me/following?type=organization")
               |> json_response(200)

      assert org_id == ctx.organization.id
    end

    test "an unpublished gym cannot be followed", ctx do
      assert ctx.as.(ctx.outsider)
             |> send_json(:post, "/api/me/follows", %{
               target_type: "organization",
               target_id: ctx.organization.id
             })
             |> response(404)
    end
  end

  describe "people" do
    test "a follow is a request; accepting it opens followers posts", ctx do
      %{as: as, member: author, outsider: follower, stranger: stranger} = ctx

      for {audience, body} <- [{"followers", "Fran PR 3:58"}, {"public", "Hello world"}] do
        assert %{"post" => %{"origin" => "profile", "audience" => ^audience}} =
                 as.(author)
                 |> send_json(:post, "/api/profile-posts", %{audience: audience, body: body})
                 |> json_response(201)
      end

      assert %{"code" => "cannot_follow_self"} =
               as.(author)
               |> send_json(:post, "/api/me/follows", %{target_type: "user", target_id: author.id})
               |> json_response(422)

      assert %{"status" => "requested"} =
               as.(follower)
               |> send_json(:post, "/api/me/follows", %{target_type: "user", target_id: author.id})
               |> json_response(200)

      drain()
      assert "follow_requested" in notifications(author)

      # Not yet a follower: public posts only.
      assert %{"posts" => [%{"body" => "Hello world"}]} =
               as.(follower) |> get("/api/people/#{author.id}/posts") |> json_response(200)

      assert %{"requests_count" => 1, "posts_count" => 2} =
               as.(author) |> get("/api/me/social") |> json_response(200)

      assert %{"entries" => [%{"follow_id" => follow_id, "person" => %{"id" => follower_id}}]} =
               as.(author) |> get("/api/me/follow-requests") |> json_response(200)

      assert follower_id == follower.id
      assert as.(stranger) |> post("/api/me/follow-requests/#{follow_id}/accept") |> response(404)
      assert as.(author) |> post("/api/me/follow-requests/#{follow_id}/accept") |> response(204)

      drain()
      assert "follow_accepted" in notifications(follower)

      assert %{"posts" => posts} =
               as.(follower) |> get("/api/people/#{author.id}/posts") |> json_response(200)

      assert length(posts) == 2

      assert %{"posts" => feed} = as.(follower) |> get("/api/me/feed") |> json_response(200)
      assert Enum.all?(feed, &(&1["origin"] == "profile" and &1["author"]["id"] == author.id))
      assert length(feed) == 2

      assert %{"my_status" => "active", "follows_me" => false, "followers_count" => 1} =
               as.(follower) |> get("/api/people/#{author.id}") |> json_response(200)

      assert %{"follows_me" => true, "my_status" => "none"} =
               as.(author) |> get("/api/people/#{follower.id}") |> json_response(200)

      assert %{"posts" => [%{"body" => "Hello world"}]} =
               as.(stranger) |> get("/api/people/#{author.id}/posts") |> json_response(200)

      # Removing a follower closes the followers posts again.
      assert as.(author) |> delete("/api/me/followers/#{follow_id}") |> response(204)

      assert %{"posts" => [_public]} =
               as.(follower) |> get("/api/people/#{author.id}/posts") |> json_response(200)

      assert %{"followers_count" => 0, "requests_count" => 0} =
               as.(author) |> get("/api/me/social") |> json_response(200)
    end

    test "comments and kudos on a profile post follow its audience", ctx do
      %{as: as, member: author, stranger: stranger} = ctx

      assert %{"post" => %{"id" => post_id}} =
               as.(author)
               |> send_json(:post, "/api/profile-posts", %{audience: "followers", body: "Hi"})
               |> json_response(201)

      assert as.(stranger)
             |> send_json(:post, "/api/profile-posts/#{post_id}/comments", %{body: "Hey"})
             |> response(404)

      assert as.(stranger)
             |> send_json(:put, "/api/profile-posts/#{post_id}/kudos", %{kudos: true})
             |> response(404)

      assert %{"comment" => %{"id" => comment_id}} =
               as.(author)
               |> send_json(:post, "/api/profile-posts/#{post_id}/comments", %{body: "Notes"})
               |> json_response(201)

      assert %{"post" => %{"kudos_count" => 1, "kudos_by_me" => true}} =
               as.(author)
               |> send_json(:put, "/api/profile-posts/#{post_id}/kudos", %{kudos: true})
               |> json_response(200)

      assert as.(author) |> delete("/api/profile-post-comments/#{comment_id}") |> response(204)
      assert as.(stranger) |> delete("/api/profile-posts/#{post_id}") |> response(404)
      assert as.(author) |> delete("/api/profile-posts/#{post_id}") |> response(204)

      assert %{"posts_count" => 0} = as.(author) |> get("/api/me/social") |> json_response(200)
    end
  end
end
