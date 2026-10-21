defmodule MilosTrainingWeb.PtSquadsControllerTest do
  @moduledoc "ADR-168: PT squads, a coach's invite-only channel with their own clients."

  use MilosTrainingWeb.ConnCase, async: false

  import Ecto.Query
  import MilosTraining.TestFixtures

  alias MilosTraining.Coaching.Relationship
  alias MilosTraining.Community.ChannelMembership
  alias MilosTraining.Community.Domain.SquadPolicy
  alias MilosTraining.{Notifications, Organizations, Repo}

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    person = fn role ->
      user = user_fixture()
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
      user
    end

    slug = Organizations.legacy_organization_slug()

    %{
      organization: organization,
      admin: person.(:admin),
      coach: person.(:coach),
      other_coach: person.(:coach),
      client: person.(:member),
      second_client: person.(:athlete),
      stranger: person.(:member),
      as: fn user -> put_bearer_token(conn, user) end,
      base: "/api/org/#{slug}/community",
      staff: "/api/org/#{slug}/staff"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp coach_client(ctx, coach, client) do
    %{"relationship" => %{"id" => id}} =
      ctx.as.(ctx.admin)
      |> send_json(:post, "#{ctx.staff}/coaching-relationships", %{
        coach_user_id: coach.id,
        client_user_id: client.id
      })
      |> json_response(201)

    id
  end

  defp channel(as, user, id) do
    as.(user)
    |> get("/api/me/clubs")
    |> json_response(200)
    |> Map.fetch!("clubs")
    |> Enum.find(&(&1["kind"] == "gym"))
    |> Map.fetch!("channels")
    |> Enum.find(&(&1["id"] == id))
  end

  defp create(ctx, body) do
    ctx.as.(ctx.coach)
    |> send_json(:post, "#{ctx.base}/squads", body)
  end

  test "a coach starts a squad with their clients; they accept and talk there", ctx do
    %{as: as, base: base, coach: coach, client: client, second_client: second} = ctx
    coach_client(ctx, coach, client)
    coach_client(ctx, coach, second)

    # The coach sees their clients to invite.
    assert %{"can_create" => true, "clients" => clients, "coached" => []} =
             as.(coach) |> get("#{base}/squads") |> json_response(200)

    assert Enum.sort(Enum.map(clients, & &1["id"])) == Enum.sort([client.id, second.id])

    # Only their own clients can be invited, and nothing is created otherwise.
    assert %{"code" => "not_your_client"} =
             ctx
             |> create(%{name: "Hyrox crew", client_ids: [ctx.stranger.id]})
             |> json_response(403)

    assert %{"coached" => []} = as.(coach) |> get("#{base}/squads") |> json_response(200)

    assert %{"squad" => %{"id" => id, "role" => "coach", "members" => members}} =
             ctx |> create(%{name: "Hyrox crew", client_ids: [client.id]}) |> json_response(201)

    assert [%{"person" => %{"id" => client_id}, "status" => "invited"}] = members
    assert client_id == client.id

    # The coach is in it and writes; the invited client hears about it but
    # doesn't see the channel until they accept.
    assert %{"participant" => true, "can_post" => true, "can_pin" => true} =
             channel(as, coach, id)

    refute channel(as, client, id)

    assert Enum.any?(
             Notifications.list_for_user(client.id),
             &(&1.type == "community_squad_invited")
           )

    assert %{"invites" => [%{"id" => ^id, "role" => "invited", "coach" => %{"id" => coach_id}}]} =
             as.(client) |> get("#{base}/squads") |> json_response(200)

    assert coach_id == coach.id

    assert %{"squad" => %{"role" => "member", "member_count" => 1}} =
             as.(client)
             |> send_json(:put, "#{base}/squads/#{id}/invite", %{accept: true})
             |> json_response(200)

    assert %{"participant" => true, "can_post" => true} = channel(as, client, id)

    assert %{"post" => _post} =
             as.(client)
             |> send_json(:post, "#{base}/posts", %{channel_id: id, body: "Wall balls again?"})
             |> json_response(201)

    # Nobody else in the gym sees it, staff included.
    refute channel(as, ctx.stranger, id)
    refute channel(as, ctx.admin, id)
    refute channel(as, ctx.other_coach, id)
    assert as.(ctx.stranger) |> get("#{base}/squads/#{id}") |> json_response(404)

    assert as.(ctx.admin)
           |> send_json(:post, "#{base}/posts", %{channel_id: id, body: "Hi"})
           |> json_response(404)

    # A member sees the people, not who hasn't answered yet.
    assert %{"squad" => %{"invite_count" => 1}} =
             as.(coach)
             |> send_json(:post, "#{base}/squads/#{id}/invites", %{user_ids: [second.id]})
             |> json_response(200)

    assert %{"squad" => %{"members" => [%{"status" => "member"}], "invite_count" => 0}} =
             as.(client) |> get("#{base}/squads/#{id}") |> json_response(200)

    # The second client declines; the squad is gone for them.
    assert %{"outcome" => "declined"} =
             as.(second)
             |> send_json(:put, "#{base}/squads/#{id}/invite", %{accept: false})
             |> json_response(200)

    assert as.(second) |> get("#{base}/squads/#{id}") |> json_response(404)
    refute channel(as, second, id)

    # Only the coach renames it, and the coach can't leave (they archive).
    assert as.(client)
           |> send_json(:patch, "#{base}/squads/#{id}", %{name: "Mine"})
           |> json_response(403)

    assert %{"squad" => %{"name" => "Hyrox squad"}} =
             as.(coach)
             |> send_json(:patch, "#{base}/squads/#{id}", %{name: "Hyrox squad"})
             |> json_response(200)

    assert %{"code" => "coach_archives_instead"} =
             as.(coach) |> delete("#{base}/squads/#{id}/membership") |> json_response(422)

    # The client leaves.
    assert %{"outcome" => "left"} =
             as.(client) |> delete("#{base}/squads/#{id}/membership") |> json_response(200)

    refute channel(as, client, id)
  end

  test "membership follows coaching", ctx do
    %{as: as, base: base, coach: coach, client: client, second_client: second} = ctx
    relationship_id = coach_client(ctx, coach, client)
    coach_client(ctx, coach, second)

    %{"squad" => %{"id" => id}} =
      ctx
      |> create(%{name: "Morning PT", client_ids: [client.id, second.id]})
      |> json_response(201)

    for user <- [client, second] do
      as.(user)
      |> send_json(:put, "#{base}/squads/#{id}/invite", %{accept: true})
      |> json_response(200)
    end

    # Ending the coaching takes the client out of that coach's squads.
    assert as.(coach)
           |> post("#{ctx.staff}/coaching-relationships/#{relationship_id}/end")
           |> json_response(200)

    refute channel(as, client, id)

    assert %{"joined" => [], "invites" => []} =
             as.(client) |> get("#{base}/squads") |> json_response(200)

    assert %{source: "dismissed"} =
             Repo.one(
               from(m in ChannelMembership,
                 where: m.channel_id == ^id and m.user_id == ^client.id
               )
             )

    # Re-checked on every read: coaching that ended another way hides it too.
    assert channel(as, second, id)

    Repo.update_all(
      from(r in Relationship, where: r.client_user_id == ^second.id and is_nil(r.ended_at)),
      set: [ended_at: DateTime.utc_now()]
    )

    refute channel(as, second, id)
    assert as.(second) |> get("#{base}/squads/#{id}") |> json_response(404)

    # Only active clients can be invited back.
    assert %{"code" => "not_your_client"} =
             as.(coach)
             |> send_json(:post, "#{base}/squads/#{id}/invites", %{user_ids: [client.id]})
             |> json_response(403)

    # A new coaching relationship makes a new invitation possible.
    coach_client(ctx, coach, client)

    assert %{"squad" => %{"invite_count" => 1}} =
             as.(coach)
             |> send_json(:post, "#{base}/squads/#{id}/invites", %{user_ids: [client.id]})
             |> json_response(200)
  end

  test "only coaches start squads; coaches and managers archive, coaches reopen", ctx do
    %{as: as, base: base, coach: coach, client: client} = ctx
    coach_client(ctx, coach, client)

    assert %{"can_create" => false} = as.(client) |> get("#{base}/squads") |> json_response(200)

    assert %{"code" => "not_a_coach"} =
             as.(client)
             |> send_json(:post, "#{base}/squads", %{name: "Mine"})
             |> json_response(422)

    %{"squad" => %{"id" => id}} = ctx |> create(%{name: "Team A"}) |> json_response(201)

    # One name per coach among live squads.
    assert ctx |> create(%{name: "team a"}) |> json_response(422)

    # Another coach can't touch it; the gym's managers may archive it.
    assert as.(ctx.other_coach) |> post("#{base}/squads/#{id}/archive") |> json_response(404)

    assert %{"outcome" => "archived"} =
             as.(ctx.admin) |> post("#{base}/squads/#{id}/archive") |> json_response(200)

    refute channel(as, coach, id)

    assert %{"coached" => [], "archived" => [%{"id" => ^id}]} =
             as.(coach) |> get("#{base}/squads") |> json_response(200)

    assert %{"squad" => %{"id" => ^id}} =
             as.(coach) |> post("#{base}/squads/#{id}/reopen") |> json_response(200)

    assert channel(as, coach, id)

    # The coach removes or un-invites.
    as.(coach)
    |> send_json(:post, "#{base}/squads/#{id}/invites", %{user_ids: [client.id]})
    |> json_response(200)

    assert %{"squad" => %{"members" => [], "invite_count" => 0}} =
             as.(coach)
             |> delete("#{base}/squads/#{id}/members/#{client.id}")
             |> json_response(200)

    assert as.(client) |> get("#{base}/squads/#{id}") |> json_response(404)
  end

  describe "SquadPolicy" do
    test "invitees are the coach's clients, deduplicated, within the squad's size" do
      clients = for _ <- 1..31, do: Ecto.UUID.generate()
      [first | _] = clients

      assert {:ok, [^first]} = SquadPolicy.invitees([first, first], clients, [], "coach")
      assert {:error, :not_your_client} = SquadPolicy.invitees(["x"], clients, [], "coach")
      assert {:error, :squad_full} = SquadPolicy.invitees(clients, clients, [], "coach")

      member = %{user_id: first, source: "invited"}
      assert {:ok, []} = SquadPolicy.invitees([first], clients, [member], "coach")

      dismissed = %{user_id: first, source: "dismissed"}
      assert {:ok, [^first]} = SquadPolicy.invitees([first], clients, [dismissed], "coach")
    end

    test "a coach runs a bounded number of squads" do
      assert :ok = SquadPolicy.can_create?([:coach], 19)
      assert {:error, :too_many_squads} = SquadPolicy.can_create?([:coach], 20)
      assert {:error, :not_a_coach} = SquadPolicy.can_create?([:member], 0)
    end

    test "a squad shows to its coach, and to members still coached by them" do
      squad = %{created_by_id: "coach"}
      member = %{source: "invited"}

      assert SquadPolicy.visible?(squad, "coach", nil, [])
      assert SquadPolicy.visible?(squad, "client", member, ["coach"])
      refute SquadPolicy.visible?(squad, "client", member, [])
      refute SquadPolicy.visible?(squad, "client", %{source: "pending_invite"}, ["coach"])
    end
  end
end
