defmodule Palee.Documents.RLSEnforcementTest do
  @moduledoc """
  ADR-252: the documents tables isolate tenants under a role that does not
  bypass RLS, the tenant trigger fills `organization_id`, and versions,
  signatures and audit events refuse UPDATE and DELETE outside the purge.
  """
  use Palee.RLSCase, async: false

  @hash String.duplicate("a", 64)

  setup %{conn: conn} do
    # Insert-only rows block the cascade of RLSCase's organization cleanup,
    # so they are purged first (on_exit callbacks run last-registered first).
    purge_leftovers()
    on_exit(&purge_leftovers/0)

    {org_s, org} = uuid()
    {other_s, other} = uuid()
    {user_s, user} = uuid()

    for {id, name} <- [{org, "rls-documents"}, {other, "rls-documents-other"}] do
      Postgrex.query!(
        conn,
        """
        INSERT INTO organizations (id, name, slug, status, inserted_at, updated_at)
        VALUES ($1, $2, $3, 'active', now(), now())
        """,
        [id, name, "#{name}-#{System.unique_integer([:positive])}"]
      )
    end

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
      [user, "rls_documents_#{System.unique_integer([:positive])}"]
    )

    %{org: {org_s, org}, other: {other_s, other}, user: {user_s, user}}
  end

  test "documents, versions, signatures and certificates stay inside their organization", ctx do
    %{conn: conn, org: {org_s, _org}, other: {other_s, _other}, user: {user_s, user}} = ctx
    {_template_s, template} = uuid()
    {_version_s, version} = uuid()
    {_signature_s, signature} = uuid()

    as_session(conn, user_s, org_s, false, fn ->
      # No organization_id given: the tenant trigger fills it from the session.
      Postgrex.query!(
        conn,
        """
        INSERT INTO document_templates (id, kind, title, requirement, inserted_at, updated_at)
        VALUES ($1, 'waiver', 'Απαλλαγή', 'mandatory', now(), now())
        """,
        [template]
      )

      Postgrex.query!(
        conn,
        """
        INSERT INTO document_versions
          (id, template_id, number, title, body, language, change_kind, content_hash,
           published_at, inserted_at)
        VALUES ($1, $2, 1, 'Απαλλαγή', 'Κείμενο', 'el', 'major', $3, now(), now())
        """,
        [version, template, @hash]
      )

      Postgrex.query!(
        conn,
        """
        INSERT INTO document_signatures
          (id, template_id, version_id, version_number, user_id, signed_at, content_hash,
           typed_name, account, evidence_hash, evidence_object_key, evidence_sha256,
           evidence_byte_size, inserted_at)
        VALUES ($1, $2, $3, 1, $4, now(), $5, 'Μαρία', '{}', $5, 'k', $5, 10, now())
        """,
        [signature, template, version, user, @hash]
      )

      Postgrex.query!(
        conn,
        """
        INSERT INTO health_certificates
          (id, user_id, issued_on, expires_on, file_key, content_type, byte_size,
           inserted_at, updated_at)
        VALUES (gen_random_uuid(), $1, '2027-01-01', '2028-01-01', $2, 'application/pdf', 10,
                now(), now())
        """,
        [user, "organizations/#{org_s}/documents/health/#{user_s}/x.pdf"]
      )
    end)

    tables = ~w(document_templates document_versions document_signatures health_certificates)

    own = as_session(conn, user_s, org_s, false, fn -> counts(conn, tables) end)
    elsewhere = as_session(conn, user_s, other_s, false, fn -> counts(conn, tables) end)
    nowhere = as_session(conn, user_s, nil, false, fn -> counts(conn, tables) end)

    assert own == [1, 1, 1, 1]
    assert elsewhere == [0, 0, 0, 0]
    assert nowhere == [0, 0, 0, 0]

    # A session without an organization cannot write a tenant row (and one in
    # another organization has its organization_id rewritten by the trigger).
    assert_raise Postgrex.Error, ~r/row-level security/, fn ->
      as_session(conn, user_s, nil, false, fn ->
        Postgrex.query!(
          conn,
          """
          INSERT INTO document_templates
            (id, organization_id, kind, title, inserted_at, updated_at)
          VALUES (gen_random_uuid(), $1, 'terms', 'x', now(), now())
          """,
          [elem(ctx.org, 1)]
        )
      end)
    end

    # Insert-only evidence.
    as_session(conn, user_s, org_s, false, fn ->
      for {sql, params} <- [
            {"UPDATE document_versions SET body = 'changed' WHERE id = $1", [version]},
            {"UPDATE document_signatures SET typed_name = 'x' WHERE id = $1", [signature]},
            {"DELETE FROM document_signatures WHERE id = $1", [signature]}
          ] do
        assert_raise Postgrex.Error, ~r/insert-only/, fn -> Postgrex.query!(conn, sql, params) end
      end

      # The purge flag (transaction-local) lifts it for deletes only.
      Postgrex.query!(conn, "BEGIN", [])
      Postgrex.query!(conn, "SELECT set_config('palee.documents_purge', 'on', true)", [])
      Postgrex.query!(conn, "DELETE FROM document_signatures WHERE id = $1", [signature])
      Postgrex.query!(conn, "DELETE FROM document_versions WHERE id = $1", [version])
      Postgrex.query!(conn, "COMMIT", [])

      assert counts(conn, ~w(document_signatures document_versions)) == [0, 0]
      Postgrex.query!(conn, "DELETE FROM health_certificates WHERE user_id = $1", [user])
      Postgrex.query!(conn, "DELETE FROM document_templates WHERE id = $1", [template])
    end)
  end

  # Runs as the suite's admin role (it sees every organization); the trigger
  # still guards the rows, so the transaction-local purge flag is set.
  defp purge_leftovers do
    admin = Application.fetch_env!(:palee, :test_database_admin)

    {:ok, conn} =
      Postgrex.start_link(
        hostname: System.get_env("DB_HOST", "localhost"),
        port: String.to_integer(System.get_env("DB_PORT", "5432")),
        username: Keyword.fetch!(admin, :username),
        password: Keyword.fetch!(admin, :password),
        database: System.get_env("DB_NAME", "palee_test#{System.get_env("MIX_TEST_PARTITION")}")
      )

    Postgrex.query!(conn, "BEGIN", [])
    Postgrex.query!(conn, "SELECT set_config('palee.documents_purge', 'on', true)", [])

    for table <- ~w(document_signatures document_audit_events document_signature_requests
                    document_versions document_templates health_certificates document_settings) do
      Postgrex.query!(
        conn,
        "DELETE FROM #{table} WHERE organization_id IN " <>
          "(SELECT id FROM organizations WHERE slug LIKE 'rls-documents%')",
        []
      )
    end

    Postgrex.query!(conn, "COMMIT", [])
    GenServer.stop(conn)
  end

  defp counts(conn, tables) do
    Enum.map(tables, fn table ->
      %{rows: [[count]]} = Postgrex.query!(conn, "SELECT count(*) FROM #{table}", [])
      count
    end)
  end
end
