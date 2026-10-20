defmodule MilosTraining.Media.PostMediaRLSTest do
  @moduledoc """
  ADR-157: post uploads are the uploader's own (media_account_objects).
  Proves under real RLS that nobody else reads, changes or attaches them.
  """

  use MilosTraining.RLSCase, async: false

  setup %{conn: conn} do
    unique = System.unique_integer([:positive])
    Postgrex.query!(conn, "SELECT set_config('app.invitation_redemption', 'true', false)", [])

    people =
      for name <- [:owner, :stranger], into: %{} do
        {id_s, id} = uuid()
        nick = "rls_media_#{name}_#{unique}"

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

  test "a post upload is readable and writable by its owner only", %{conn: conn, people: people} do
    {owner_s, owner} = people.owner
    {stranger_s, stranger} = people.stranger
    {_media_s, media} = uuid()

    as_session(conn, owner_s, nil, false, fn ->
      Postgrex.query!(
        conn,
        """
        INSERT INTO media_account_objects
          (id, user_id, purpose, object_key, content_type, status, inserted_at, updated_at)
        VALUES ($1, $2, 'post_photo', $3, 'image/jpeg', 'processing', now(), now())
        """,
        [media, owner, "users/#{owner_s}/media/posts/x/original.jpg"]
      )
    end)

    as_session(conn, stranger_s, nil, false, fn ->
      assert %{num_rows: 0} =
               Postgrex.query!(conn, "SELECT id FROM media_account_objects WHERE id = $1", [media])

      assert %{num_rows: 0} =
               Postgrex.query!(
                 conn,
                 "UPDATE media_account_objects SET alt_text = 'x', attached_type = 'profile_post', attached_id = $2 WHERE id = $1",
                 [media, stranger]
               )

      # Nor can they plant an upload in someone else's name.
      assert_raise Postgrex.Error, ~r/row-level security/, fn ->
        Postgrex.query!(
          conn,
          """
          INSERT INTO media_account_objects
            (id, user_id, purpose, object_key, content_type, inserted_at, updated_at)
          VALUES (gen_random_uuid(), $1, 'post_video', 'k', 'video/mp4', now(), now())
          """,
          [owner]
        )
      end
    end)

    as_session(conn, owner_s, nil, false, fn ->
      assert %{rows: [["processing", nil]]} =
               Postgrex.query!(
                 conn,
                 "SELECT status, alt_text FROM media_account_objects WHERE id = $1",
                 [media]
               )

      Postgrex.query!(conn, "DELETE FROM media_account_objects WHERE id = $1", [media])
    end)
  end
end
