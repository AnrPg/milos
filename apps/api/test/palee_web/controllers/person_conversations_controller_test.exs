defmodule PaleeWeb.PersonConversationsControllerTest do
  @moduledoc """
  ADR-193: Buddies (mutual follows), public and private accounts, people
  search and person-to-person conversations with an inbox, message requests
  and declines, all without a gym.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Notifications, Organizations}

  setup %{conn: conn} do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    %{as: fn user -> put_bearer_token(conn, user) end}
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp follow!(ctx, from, to) do
    ctx.as.(from) |> send_json(:post, "/api/me/follows", %{target_type: "user", target_id: to.id})
  end

  defp buddies!(ctx, one, other) do
    follow!(ctx, one, other)
    follow!(ctx, other, one)

    for {who, follower} <- [{other, one}, {one, other}] do
      [request] = json_response(get(ctx.as.(who), "/api/me/follow-requests"), 200)["entries"]
      assert request["person"]["id"] == follower.id

      assert response(
               post(ctx.as.(who), "/api/me/follow-requests/#{request["follow_id"]}/accept"),
               204
             )
    end
  end

  defp open!(ctx, from, to) do
    ctx.as.(from)
    |> send_json(:post, "/api/me/conversations", %{person_id: to.id})
    |> json_response(200)
    |> Map.fetch!("conversation")
  end

  defp say!(ctx, from, conversation_id, body, operation \\ Ecto.UUID.generate()) do
    ctx.as.(from)
    |> send_json(:post, "/api/me/conversations/#{conversation_id}/messages", %{
      body: body,
      client_operation_id: operation
    })
    |> json_response(201)
    |> Map.fetch!("message")
  end

  defp folder(ctx, user, folder) do
    ctx.as.(user)
    |> get("/api/me/conversations?folder=#{folder}")
    |> json_response(200)
    |> Map.fetch!("conversations")
  end

  defp notifications(user) do
    Oban.drain_queue(queue: :notifications, with_safety: false)
    Notifications.list_for_user(user.id) |> Enum.map(& &1.type)
  end

  test "Buddies write to each other without a gym and it reaches the inbox", ctx do
    ana = user_fixture()
    ben = user_fixture()
    buddies!(ctx, ana, ben)

    person = json_response(get(ctx.as.(ana), "/api/people/#{ben.id}"), 200)
    assert person["buddy"]

    assert person["follow_groups"] == %{
             "buddies" => 1,
             "followers_only" => 0,
             "following_only" => 0
           }

    summary = json_response(get(ctx.as.(ana), "/api/me/social"), 200)
    assert summary["follow_groups"]["buddies"] == 1
    assert summary["privacy"] == %{"private_account" => true, "searchable" => true}

    buddies = json_response(get(ctx.as.(ana), "/api/me/buddies-list"), 200)["entries"]
    assert [%{"person" => %{"id" => ben_id, "buddy" => true}}] = buddies
    assert ben_id == ben.id
    assert json_response(get(ctx.as.(ana), "/api/me/followers"), 200)["entries"] == []
    assert json_response(get(ctx.as.(ana), "/api/me/following"), 200)["entries"] == []

    conversation = open!(ctx, ana, ben)
    assert conversation["buddy"]
    assert conversation["folder"] == "inbox"
    # Nothing shows for Ben until the first message.
    assert folder(ctx, ben, "inbox") == []

    operation = Ecto.UUID.generate()
    message = say!(ctx, ana, conversation["id"], "Πάμε 07:00;", operation)
    assert message["mine"]
    # A retry of the same operation answers the same message.
    assert say!(ctx, ana, conversation["id"], "Πάμε 07:00;", operation)["id"] == message["id"]

    assert [%{"id" => id, "unread" => true, "last_message" => %{"body" => "Πάμε 07:00;"}}] =
             folder(ctx, ben, "inbox")

    assert id == conversation["id"]

    assert json_response(get(ctx.as.(ben), "/api/me/conversations/unread-count"), 200) ==
             %{"inbox" => 1, "requests" => 0}

    assert "person_message" in notifications(ben)

    assert json_response(post(ctx.as.(ben), "/api/me/conversations/#{id}/read"), 200)[
             "conversation"
           ]["unread"] == false

    assert [%{"body" => "Πάμε 07:00;"}] =
             json_response(get(ctx.as.(ben), "/api/me/conversations/#{id}/messages"), 200)[
               "messages"
             ]
  end

  test "a stranger's message waits in requests; accept, reply and decline", ctx do
    ana = user_fixture()
    ben = user_fixture()
    cleo = user_fixture()

    conversation = open!(ctx, ana, ben)
    say!(ctx, ana, conversation["id"], "Hi!")
    assert folder(ctx, ben, "inbox") == []
    assert [%{"folder" => "requests"}] = folder(ctx, ben, "requests")
    assert "message_request" in notifications(ben)
    refute "person_message" in notifications(ben)

    assert json_response(
             post(ctx.as.(ben), "/api/me/conversations/#{conversation["id"]}/accept"),
             200
           )[
             "conversation"
           ]["folder"] == "inbox"

    # Declining a request hides it for good; the sender can still write.
    other = open!(ctx, cleo, ben)
    say!(ctx, cleo, other["id"], "Hey")
    assert response(post(ctx.as.(ben), "/api/me/conversations/#{other["id"]}/decline"), 204)
    assert json_response(get(ctx.as.(ben), "/api/me/conversations/#{other["id"]}"), 404)
    say!(ctx, cleo, other["id"], "Still there?")
    assert folder(ctx, ben, "requests") == []
  end

  test "people in the same gym reach the inbox; a block makes the person unreachable", ctx do
    {:ok, organization} =
      Organizations.create_organization(%{name: "DM Gym #{System.unique_integer([:positive])}"})

    [ana, ben] =
      for _ <- 1..2 do
        user = user_fixture()

        {:ok, _} =
          Organizations.add_membership(%{
            organization_id: organization.id,
            user_id: user.id,
            role: :member,
            status: :active,
            joined_at: DateTime.utc_now()
          })

        user
      end

    conversation = open!(ctx, ana, ben)
    say!(ctx, ana, conversation["id"], "Καλημέρα")
    assert [_] = folder(ctx, ben, "inbox")

    ctx.as.(ben) |> send_json(:post, "/api/me/blocks", %{user_id: ana.id}) |> response(200)

    assert ctx.as.(ana)
           |> send_json(:post, "/api/me/conversations", %{person_id: ben.id})
           |> json_response(404)
  end

  test "a public person is followed at once; going public accepts waiting requests", ctx do
    ana = user_fixture()
    ben = user_fixture()
    cleo = user_fixture()

    assert json_response(follow!(ctx, cleo, ben), 200)["status"] == "requested"

    assert json_response(
             ctx.as.(ben) |> send_json(:put, "/api/me/social/privacy", %{private_account: false}),
             200
           ) == %{"private_account" => false, "searchable" => true}

    assert json_response(get(ctx.as.(cleo), "/api/me/follows/user/#{ben.id}"), 200)["status"] ==
             "active"

    assert json_response(follow!(ctx, ana, ben), 200)["status"] == "active"
    assert "new_follower" in notifications(ben)
    refute json_response(get(ctx.as.(ana), "/api/people/#{ben.id}"), 200)["private"]

    groups = json_response(get(ctx.as.(ben), "/api/me/social"), 200)["follow_groups"]
    assert groups == %{"buddies" => 0, "followers_only" => 2, "following_only" => 0}
  end

  test "people search finds public people and the people you know, never private strangers",
       ctx do
    unique = System.unique_integer([:positive])
    me = user_fixture()
    public = user_fixture(%{nickname: "zorbas_pub_#{unique}"})
    private = user_fixture(%{nickname: "zorbas_priv_#{unique}"})
    hidden = user_fixture(%{nickname: "zorbas_hid_#{unique}"})
    buddy = user_fixture(%{nickname: "zorbas_bud_#{unique}"})

    ctx.as.(public) |> send_json(:put, "/api/me/social/privacy", %{private_account: false})

    ctx.as.(hidden)
    |> send_json(:put, "/api/me/social/privacy", %{private_account: false, searchable: false})

    buddies!(ctx, me, buddy)

    found =
      ctx.as.(me)
      |> get("/api/people-search?q=zorbas_")
      |> json_response(200)
      |> Map.fetch!("people")

    assert Enum.map(found, &{&1["id"], &1["relation"]}) == [
             {buddy.id, "buddy"},
             {public.id, "public"}
           ]

    refute Enum.any?(found, &(&1["id"] in [private.id, hidden.id]))
    assert json_response(get(ctx.as.(me), "/api/people-search?q=z"), 200)["people"] == []
  end
end
