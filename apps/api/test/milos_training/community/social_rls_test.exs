defmodule MilosTraining.Community.SocialRLSTest do
  @moduledoc """
  ADR-142 (P2-M2): follows and profile posts are account-scoped. Proves under
  real RLS that a follower cannot accept their own request, that only the
  followed person can, and that a followers post reaches active followers
  only while a public post reaches everyone.
  """

  use MilosTraining.RLSCase, async: false

  setup %{conn: conn} do
    unique = System.unique_integer([:positive])
    Postgrex.query!(conn, "SELECT set_config('app.invitation_redemption', 'true', false)", [])

    people =
      for name <- [:author, :follower, :stranger], into: %{} do
        {id_s, id} = uuid()
        nick = "rls_social_#{name}_#{unique}"

        Postgrex.query!(
          conn,
          """
          INSERT INTO users (id, nickname, display_nickname, password_hash, role, email, inserted_at, updated_at)
          VALUES ($1, $2::text, $2::text, 'x', 'member', $2::text || '@placeholder.invalid', now(), now())
          """,
          [id, nick]
        )

        {name, {id_s, id}}
      end

    Postgrex.query!(conn, "SELECT set_config('app.invitation_redemption', '', false)", [])
    %{people: people}
  end

  test "a person follow starts as a request only the followed person accepts", %{
    conn: conn,
    people: people
  } do
    {author_s, author} = people.author
    {follower_s, follower} = people.follower
    {stranger_s, _stranger} = people.stranger

    as_session(conn, follower_s, nil, false, fn ->
      assert_raise Postgrex.Error, ~r/row-level security/, fn ->
        insert_follow(conn, follower, author, "active")
      end

      insert_follow(conn, follower, author, "requested")

      # The follower cannot promote their own request.
      assert %{num_rows: 0} =
               Postgrex.query!(
                 conn,
                 "UPDATE community_follows SET status = 'active' WHERE user_id = $1",
                 [follower]
               )
    end)

    as_session(conn, stranger_s, nil, false, fn ->
      assert follow_statuses(conn, follower) == []
    end)

    as_session(conn, author_s, nil, false, fn ->
      assert follow_statuses(conn, follower) == ["requested"]

      assert %{num_rows: 1} =
               Postgrex.query!(
                 conn,
                 "UPDATE community_follows SET status = 'active', accepted_at = now() WHERE user_id = $1",
                 [follower]
               )
    end)

    as_session(conn, follower_s, nil, false, fn ->
      assert follow_statuses(conn, follower) == ["active"]
    end)
  end

  test "a followers post reaches active followers; a public post reaches everyone", %{
    conn: conn,
    people: people
  } do
    {author_s, author} = people.author
    {follower_s, follower} = people.follower
    {stranger_s, _stranger} = people.stranger

    as_session(conn, follower_s, nil, false, fn ->
      insert_follow(conn, follower, author, "requested")
    end)

    as_session(conn, author_s, nil, false, fn ->
      for audience <- ~w(followers public) do
        Postgrex.query!(
          conn,
          """
          INSERT INTO community_profile_posts (id, user_id, audience, body, inserted_at, updated_at)
          VALUES (gen_random_uuid(), $1, $2::text, $2::text, now(), now())
          """,
          [author, audience]
        )
      end

      assert audiences(conn, author) == ["followers", "public"]
    end)

    # A pending request is not a follow yet.
    as_session(conn, follower_s, nil, false, fn ->
      assert audiences(conn, author) == ["public"]
    end)

    as_session(conn, author_s, nil, false, fn ->
      Postgrex.query!(
        conn,
        "UPDATE community_follows SET status = 'active' WHERE user_id = $1",
        [follower]
      )
    end)

    as_session(conn, follower_s, nil, false, fn ->
      assert audiences(conn, author) == ["followers", "public"]

      # Readers cannot write in the author's name.
      assert_raise Postgrex.Error, ~r/row-level security/, fn ->
        Postgrex.query!(
          conn,
          """
          INSERT INTO community_profile_posts (id, user_id, audience, body, inserted_at, updated_at)
          VALUES (gen_random_uuid(), $1, 'public', 'x', now(), now())
          """,
          [author]
        )
      end
    end)

    as_session(conn, stranger_s, nil, false, fn ->
      assert audiences(conn, author) == ["public"]
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

  defp follow_statuses(conn, follower) do
    %{rows: rows} =
      Postgrex.query!(conn, "SELECT status FROM community_follows WHERE user_id = $1", [follower])

    List.flatten(rows)
  end

  defp audiences(conn, author) do
    %{rows: rows} =
      Postgrex.query!(
        conn,
        "SELECT audience FROM community_profile_posts WHERE user_id = $1 ORDER BY audience",
        [author]
      )

    List.flatten(rows)
  end
end
