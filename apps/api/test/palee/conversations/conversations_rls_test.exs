defmodule Palee.Conversations.ConversationsRLSTest do
  @moduledoc """
  ADR-193 under real RLS: a public person can be followed at once (a private
  one only by request); only the pair reads a person conversation; nobody
  declines or reads for the other side; a block stops new messages.
  """

  use Palee.RLSCase, async: false

  setup %{conn: conn} do
    unique = System.unique_integer([:positive])
    Postgrex.query!(conn, "SELECT set_config('app.invitation_redemption', 'true', false)", [])

    people =
      for name <- [:ana, :ben, :stranger], into: %{} do
        {id_s, id} = uuid()
        nick = "rls_conv_#{name}_#{unique}"

        Postgrex.query!(
          conn,
          """
          WITH login AS (
            INSERT INTO logins (id, email, password_hash, inserted_at, updated_at)
            VALUES (gen_random_uuid(), $2::text || '@placeholder.invalid', 'x', now(), now())
            RETURNING id
          )
          INSERT INTO users (id, nickname, display_nickname, role, login_id, inserted_at, updated_at)
          SELECT $1, $2::text, $2::text, 'member', login.id, now(), now() FROM login
          """,
          [id, nick]
        )

        {name, {id_s, id}}
      end

    Postgrex.query!(conn, "SELECT set_config('app.invitation_redemption', '', false)", [])
    %{people: people}
  end

  test "only a public person can be followed at once", %{conn: conn, people: people} do
    {ana_s, ana} = people.ana
    {ben_s, ben} = people.ben

    as_session(conn, ana_s, nil, false, fn ->
      assert_raise Postgrex.Error, ~r/row-level security/, fn ->
        insert_follow(conn, ana, ben, "active")
      end
    end)

    as_session(conn, ben_s, nil, false, fn ->
      Postgrex.query!(
        conn,
        """
        INSERT INTO community_social_settings (user_id, share_bookings, private_account, inserted_at, updated_at)
        VALUES ($1, false, false, now(), now())
        """,
        [ben]
      )
    end)

    as_session(conn, ana_s, nil, false, fn -> insert_follow(conn, ana, ben, "active") end)
  end

  test "only the pair reads it, each side keeps its own marks, a block stops writing", %{
    conn: conn,
    people: people
  } do
    {ana_s, ana} = people.ana
    {ben_s, ben} = people.ben
    {stranger_s, _stranger} = people.stranger
    {a, b} = if ana_s < ben_s, do: {ana, ben}, else: {ben, ana}
    {_conversation_s, conversation} = uuid()
    ben_side = if b == ben, do: "b", else: "a"
    ana_side = if ben_side == "b", do: "a", else: "b"

    as_session(conn, ana_s, nil, false, fn ->
      Postgrex.query!(
        conn,
        """
        INSERT INTO person_conversations
          (id, user_a_id, user_b_id, started_by_id, a_folder, b_folder, inserted_at, updated_at)
        VALUES ($1, $2, $3, $4, 'inbox', 'requests', now(), now())
        """,
        [conversation, a, b, ana]
      )

      insert_message(conn, conversation, a, b, ana)

      # Ana cannot decline or read for Ben.
      assert_raise Postgrex.Error, ~r/only its own side/, fn ->
        Postgrex.query!(
          conn,
          "UPDATE person_conversations SET #{ben_side}_folder = 'declined' WHERE id = $1",
          [conversation]
        )
      end

      assert_raise Postgrex.Error, ~r/only its own side/, fn ->
        Postgrex.query!(
          conn,
          "UPDATE person_conversations SET #{ben_side}_read_at = now() WHERE id = $1",
          [conversation]
        )
      end

      Postgrex.query!(
        conn,
        "UPDATE person_conversations SET #{ana_side}_read_at = now() WHERE id = $1",
        [conversation]
      )
    end)

    as_session(conn, stranger_s, nil, false, fn ->
      assert %{rows: []} = Postgrex.query!(conn, "SELECT 1 FROM person_conversations", [])
      assert %{rows: []} = Postgrex.query!(conn, "SELECT 1 FROM person_messages", [])
    end)

    as_session(conn, ben_s, nil, false, fn ->
      assert %{num_rows: 1} = Postgrex.query!(conn, "SELECT 1 FROM person_messages", [])

      Postgrex.query!(
        conn,
        "INSERT INTO community_user_blocks (id, user_id, blocked_user_id, inserted_at) VALUES (gen_random_uuid(), $1, $2, now())",
        [ben, ana]
      )
    end)

    as_session(conn, ana_s, nil, false, fn ->
      assert_raise Postgrex.Error, ~r/row-level security/, fn ->
        insert_message(conn, conversation, a, b, ana)
      end
    end)
  end

  defp insert_follow(conn, follower, target, status) do
    Postgrex.query!(
      conn,
      """
      INSERT INTO community_follows (id, user_id, target_type, target_id, status, inserted_at, updated_at)
      VALUES (gen_random_uuid(), $1, 'user', $2, $3, now(), now())
      """,
      [follower, target, status]
    )
  end

  defp insert_message(conn, conversation, a, b, author) do
    Postgrex.query!(
      conn,
      """
      INSERT INTO person_messages (id, conversation_id, user_a_id, user_b_id, author_id, body, inserted_at)
      VALUES (gen_random_uuid(), $1, $2, $3, $4, 'hi', now())
      """,
      [conversation, a, b, author]
    )
  end
end
