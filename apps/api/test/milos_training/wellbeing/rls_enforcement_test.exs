defmodule MilosTraining.Wellbeing.RLSEnforcementTest do
  @moduledoc """
  Proves what `injury_reports_owner_or_tenant_policy` actually enforces against
  a genuine non-superuser connection. The rest of the suite runs as a Postgres
  superuser and never exercises the policy at all (see MilosTraining.RLSCase),
  so without this the policy's real behaviour is never observed.

  The policy's owner branch is deliberately permissive across organizations
  (F-28 product decision): a member's health records follow them between gyms.
  This locks that in at the database layer, where it is easy to tighten by
  accident while fixing something else.
  """
  use MilosTraining.RLSCase, async: false

  test "a member reads their own injury reports across organizations, by design",
       %{conn: conn} do
    {user_id_s, user_id} = uuid()
    {org_a_id_s, org_a_id} = uuid()
    {org_b_id_s, org_b_id} = uuid()

    Postgrex.query!(
      conn,
      """
      INSERT INTO users (id, nickname, display_nickname, password_hash, role, email, inserted_at, updated_at)
      VALUES ($1, $2::text, $2::text, 'x', 'member', $2::text || '@placeholder.invalid', now(), now())
      """,
      [user_id, "rls_wellbeing_user_#{System.unique_integer([:positive])}"]
    )

    for {org_id, slug} <- [{org_a_id, "rls-wellbeing-a"}, {org_b_id, "rls-wellbeing-b"}] do
      Postgrex.query!(
        conn,
        """
        INSERT INTO organizations (id, name, slug, status, inserted_at, updated_at)
        VALUES ($1, $2, $2, 'active', now(), now())
        """,
        [org_id, "#{slug}-#{System.unique_integer([:positive])}"]
      )
    end

    # The member files one report in each organization.
    for {org_id, area, org_id_s} <- [
          {org_a_id, "shoulder", org_a_id_s},
          {org_b_id, "knee", org_b_id_s}
        ] do
      as_session(conn, user_id_s, org_id_s, false, fn ->
        Postgrex.query!(
          conn,
          """
          INSERT INTO injury_reports
            (id, user_id, organization_id, body_area, severity, status, visibility,
             started_on, reported_by_id, reported_by_role, inserted_at, updated_at)
          VALUES ($1, $2, $3, $4, 'moderate', 'active', 'user_and_admin',
                  CURRENT_DATE, $2, 'self', now(), now())
          """,
          [Ecto.UUID.dump!(Ecto.UUID.generate()), user_id, org_id, area]
        )
      end)
    end

    # Now read as the member with ONLY organization B open.
    areas =
      as_session(conn, user_id_s, org_b_id_s, false, fn ->
        %{rows: rows} =
          Postgrex.query!(conn, "SELECT body_area FROM injury_reports WHERE user_id = $1", [
            user_id
          ])

        List.flatten(rows)
      end)

    assert "knee" in areas

    # INTENTIONAL (F-28, decided 2026-08-07). The policy is
    #   user_id = app.user_id OR organization_id = app.organization_id
    # so the owner branch alone satisfies it and organization A's report is
    # returned while only organization B is open. Health records belong to the
    # member, not the gym, so they travel with them.
    #
    # This is the ONLY sanctioned cross-organization read in the tenancy model.
    # It is safe specifically because the owner branch can only ever match the
    # acting account's own rows - it cannot expose another member's records.
    # Organization-scoped views (the admin injury list and analytics summary)
    # deliberately do NOT use this predicate; see
    # EctoWellbeingStore.scoped_to_tenant/1.
    assert "shoulder" in areas

    as_session(conn, user_id_s, nil, false, fn ->
      Postgrex.query!(conn, "DELETE FROM injury_reports WHERE user_id = $1", [user_id])
    end)

    Postgrex.query!(conn, "DELETE FROM organizations WHERE id = ANY($1)", [[org_a_id, org_b_id]])
    Postgrex.query!(conn, "DELETE FROM users WHERE id = $1", [user_id])
  end
end
