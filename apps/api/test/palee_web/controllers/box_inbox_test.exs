defmodule PaleeWeb.BoxInboxTest do
  @moduledoc """
  ADR-282: anyone writes to a box, and the box answers from one shared
  inbox worked out from the roles; «Προπόνηση» and «Φέρε τον coach» bring
  in coaches; a newcomer waits for an answer after a few messages and can
  be blocked; notifications go to everyone until someone answers.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Coaching, Notifications, Organizations, Repo}
  alias Palee.Application.{PublishBoxPublicProfile, UpdateBoxPublicProfile}

  setup %{conn: conn} do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    box = fn publish? ->
      {:ok, organization} =
        Organizations.create_organization(%{
          name: "Inbox Gym #{System.unique_integer([:positive])}"
        })

      person = fn roles, attrs ->
        user = user_fixture()

        if roles != [] do
          {:ok, _membership} =
            Organizations.add_membership(
              Map.merge(
                %{
                  organization_id: organization.id,
                  user_id: user.id,
                  role: hd(roles),
                  roles: roles,
                  status: :active,
                  joined_at: DateTime.utc_now()
                },
                attrs
              )
            )
        end

        user
      end

      owner = person.([:owner], %{})

      if publish? do
        {:ok, owner_context} = Organizations.resolve_tenant_context(owner, organization.slug)

        {:ok, profile} =
          UpdateBoxPublicProfile.call(owner_context, %{
            "about" => "Γράψε μας.",
            "disciplines" => ["crossfit"]
          })

        {:ok, _profile} =
          PublishBoxPublicProfile.publish(owner_context, %{"lock_version" => profile.lock_version})
      end

      %{organization: organization, owner: owner, person: person}
    end

    %{box: box, as: fn user -> put_bearer_token(conn, user) end}
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp write(ctx, user, slug, body, extra \\ %{}) do
    ctx.as.(user)
    |> send_json(
      :post,
      "/api/boxes/#{slug}/conversation/messages",
      Map.merge(%{body: body}, extra)
    )
  end

  defp open!(ctx, user, slug),
    do:
      ctx.as.(user)
      |> post("/api/boxes/#{slug}/conversation")
      |> json_response(200)
      |> get_in(["conversation", "thread_id"])

  defp inbox(ctx, user, slug),
    do:
      ctx.as.(user)
      |> get("/api/org/#{slug}/me/threads")
      |> json_response(200)
      |> Map.fetch!("threads")
      |> Enum.filter(&(&1["context_type"] == "box"))

  defp reply(ctx, user, slug, thread_id, body),
    do:
      ctx.as.(user)
      |> send_json(:post, "/api/org/#{slug}/me/threads/#{thread_id}/messages", %{body: body})

  defp drain, do: Oban.drain_queue(queue: :notifications, with_safety: false, with_recursion: true)

  defp inbox_notices(user),
    do:
      user.id
      |> Notifications.list_for_user()
      |> Enum.filter(&(to_string(&1.type) == "box_inbox_message"))

  test "a newcomer writes to a published box and its whole inbox reads and answers", ctx do
    %{organization: organization, owner: owner, person: person} = ctx.box.(true)
    slug = organization.slug
    front_desk = person.([:front_desk], %{})
    coach = person.([:coach], %{})
    stranger = user_fixture()

    thread_id = open!(ctx, stranger, slug)

    assert %{"message" => %{"message_type" => "chat", "topic" => "membership"}} =
             write(ctx, stranger, slug, "Έχετε τμήμα για αρχάριους;", %{topic: "membership"})
             |> json_response(201)

    drain()

    # Everyone in the inbox hears about the first message; the coach does not.
    assert [%{payload: %{"box_name" => _, "topic" => "membership"}}] = inbox_notices(owner)
    assert [_] = inbox_notices(front_desk)
    assert [] = inbox_notices(coach)

    # Someone hired after the thread opened still sees it, flagged «Νέος».
    accountant = person.([:accountant], %{})

    assert [%{"id" => ^thread_id, "box_person" => %{"newcomer" => true, "blocked" => false}}] =
             inbox(ctx, accountant, slug)

    assert [] = inbox(ctx, coach, slug)

    assert ctx.as.(coach)
           |> get("/api/org/#{slug}/me/threads/#{thread_id}/messages")
           |> json_response(403)

    assert %{"message" => %{"message_type" => "box_message"}} =
             reply(ctx, front_desk, slug, thread_id, "Ναι, κάθε Τρίτη.") |> json_response(201)

    drain()

    # The one who answered hears the next message; the others do not.
    write(ctx, stranger, slug, "Τέλεια, τι ώρα;") |> json_response(201)
    drain()

    assert [_, _] = inbox_notices(front_desk)
    assert [_] = inbox_notices(owner)

    assert [%{"last_message" => %{"body" => "Τέλεια, τι ώρα;", "sender_id" => sender}}] =
             inbox(ctx, owner, slug)

    assert sender == stranger.id
  end

  test "a newcomer waits for an answer after a few messages; a client never does", ctx do
    %{organization: organization, owner: owner} = ctx.box.(true)
    slug = organization.slug
    stranger = user_fixture()
    thread_id = open!(ctx, stranger, slug)

    for n <- 1..3, do: write(ctx, stranger, slug, "Μήνυμα #{n}") |> json_response(201)

    assert %{"code" => "awaiting_box_reply"} =
             write(ctx, stranger, slug, "Και ένα ακόμα") |> json_response(429)

    reply(ctx, owner, slug, thread_id, "Σε ακούμε!") |> json_response(201)
    write(ctx, stranger, slug, "Ευχαριστώ") |> json_response(201)
  end

  test "a member writes to their box even when its page is not published", ctx do
    %{organization: organization, owner: owner, person: person} = ctx.box.(false)
    slug = organization.slug
    member = person.([:member], %{})

    thread_id = open!(ctx, member, slug)
    for n <- 1..4, do: write(ctx, member, slug, "Ερώτηση #{n}") |> json_response(201)

    # The member reads it in Μηνύματα › Box, not among the gym's threads.
    assert %{"conversations" => [%{"thread_id" => ^thread_id, "box" => %{"slug" => ^slug}}]} =
             ctx.as.(member) |> get("/api/me/box-conversations") |> json_response(200)

    assert [] = inbox(ctx, member, slug)

    assert [%{"id" => ^thread_id, "box_person" => %{"newcomer" => false}}] =
             inbox(ctx, owner, slug)
  end

  test "«Προπόνηση» brings in the person's coach, who answers for the box", ctx do
    %{organization: organization, owner: owner, person: person} = ctx.box.(true)
    slug = organization.slug
    coach = person.([:coach], %{})
    other_coach = person.([:coach], %{})
    member = person.([:member], %{})

    {:ok, _} =
      Coaching.start_relationship(%{organization_id: organization.id}, %{
        coach_user_id: coach.id,
        client_user_id: member.id,
        origin: "assigned"
      })

    thread_id = open!(ctx, member, slug)
    write(ctx, member, slug, "Πονάει ο ώμος στα snatch", %{topic: "training"}) |> json_response(201)
    drain()

    assert [%{"id" => ^thread_id}] = inbox(ctx, coach, slug)
    assert [_] = inbox_notices(coach)
    assert [] = inbox(ctx, other_coach, slug)
    assert [_] = inbox_notices(owner)

    assert %{"message" => %{"message_type" => "box_message"}} =
             reply(ctx, coach, slug, thread_id, "Κάνε τα με PVC σήμερα") |> json_response(201)
  end

  test "«Προπόνηση» without a coach goes to the head coaches", ctx do
    %{organization: organization, person: person} = ctx.box.(true)
    slug = organization.slug
    head_coach = person.([:coach], %{coach_scope: :all})
    coach = person.([:coach], %{})
    stranger = user_fixture()

    thread_id = open!(ctx, stranger, slug)
    write(ctx, stranger, slug, "Κάνετε προετοιμασία Hyrox;", %{topic: "training"}) |> json_response(201)

    assert [%{"id" => ^thread_id}] = inbox(ctx, head_coach, slug)
    assert [] = inbox(ctx, coach, slug)
  end

  test "«Φέρε τον coach» brings any coach of the box into the thread", ctx do
    %{organization: organization, owner: owner, person: person} = ctx.box.(true)
    slug = organization.slug
    coach = person.([:coach], %{})
    front_desk = person.([:front_desk], %{})
    member = person.([:member], %{})
    thread_id = open!(ctx, member, slug)
    write(ctx, member, slug, "Ποιο πρόγραμμα να ακολουθήσω;") |> json_response(201)
    drain()

    base = "/api/org/#{slug}/me/threads/#{thread_id}"

    assert %{"coaches" => [%{"id" => coach_id, "in_thread" => false}]} =
             ctx.as.(owner) |> get("#{base}/coaches") |> json_response(200)

    assert coach_id == coach.id

    # Only a coach of the box can be brought in, and only by the inbox.
    assert %{"code" => "not_a_coach"} =
             ctx.as.(owner)
             |> send_json(:post, "#{base}/coaches", %{user_id: front_desk.id})
             |> json_response(422)

    assert ctx.as.(coach)
           |> send_json(:post, "#{base}/coaches", %{user_id: coach.id})
           |> json_response(403)

    assert %{"thread" => %{"participants" => participants}} =
             ctx.as.(owner)
             |> send_json(:post, "#{base}/coaches", %{user_id: coach.id})
             |> json_response(200)

    assert Enum.any?(participants, &(&1["user_id"] == coach.id and &1["joined_as"] == "coach"))

    drain()
    assert [%{payload: %{"brought_in_by" => _}}] = inbox_notices(coach)

    assert %{"message" => %{"message_type" => "box_message"}} =
             reply(ctx, coach, slug, thread_id, "Ξεκίνα με το Foundations") |> json_response(201)
  end

  test "the inbox blocks a newcomer, never a client", ctx do
    %{organization: organization, owner: owner, person: person} = ctx.box.(true)
    slug = organization.slug
    stranger = user_fixture()
    member = person.([:member], %{})

    stranger_thread = open!(ctx, stranger, slug)
    write(ctx, stranger, slug, "spam") |> json_response(201)
    member_thread = open!(ctx, member, slug)

    assert %{"blocked" => true} =
             ctx.as.(owner)
             |> put("/api/org/#{slug}/me/threads/#{stranger_thread}/block")
             |> json_response(200)

    assert %{"code" => "blocked_by_box"} = write(ctx, stranger, slug, "ξανά") |> json_response(403)
    assert %{"code" => "blocked_by_box"} =
             ctx.as.(stranger) |> post("/api/boxes/#{slug}/conversation") |> json_response(403)

    assert %{"code" => "client_not_blockable"} =
             ctx.as.(owner)
             |> put("/api/org/#{slug}/me/threads/#{member_thread}/block")
             |> json_response(422)

    assert %{"blocked" => false} =
             ctx.as.(owner)
             |> delete("/api/org/#{slug}/me/threads/#{stranger_thread}/block")
             |> json_response(200)

    write(ctx, stranger, slug, "συγγνώμη") |> json_response(201)
  end

  test "someone who leaves the inbox loses the box's threads", ctx do
    %{organization: organization, person: person} = ctx.box.(true)
    slug = organization.slug
    front_desk = person.([:front_desk], %{})
    stranger = user_fixture()
    thread_id = open!(ctx, stranger, slug)
    write(ctx, stranger, slug, "Γεια") |> json_response(201)

    assert [_] = inbox(ctx, front_desk, slug)

    Repo.query!(
      "UPDATE organization_memberships SET roles = ARRAY['janitor'], role = 'janitor' WHERE user_id = $1",
      [Ecto.UUID.dump!(front_desk.id)]
    )

    assert [] = inbox(ctx, front_desk, slug)

    assert ctx.as.(front_desk)
           |> get("/api/org/#{slug}/me/threads/#{thread_id}/messages")
           |> json_response(403)
  end
end
