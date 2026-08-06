defmodule MilosTraining.Wellbeing.RLSEnforcementTest do
  @moduledoc """
  Proves what `injury_reports_owner_or_tenant_policy` actually enforces against
  a genuine non-superuser connection. The rest of the suite runs as a Postgres
  superuser and never exercises the policy at all (see MilosTraining.RLSCase),
  which is exactly how the gap asserted here stayed invisible.
  """
  use MilosTraining.RLSCase, async: false

  test "the policy's OR lets a member read an injury report from an organization they do not have open",
       %{conn: conn} do
    {user_id_s, user_id} = uuid()
    {org_a_id_s, org_a_id} = uuid()
    {org_b_id_s, org_b_id} = uuid()

    Postgrex.query!(
      conn,
      """
      INSERT INTO users (id, nickname, display_nickname, password_hash, role, inserted_at, updated_at)
      VALUES ($1, $2, $2, 'x', 'member', now(), now())
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

    # CONFIRMED CROSS-TENANT READ. The policy is
    #   user_id = app.user_id OR organization_id = app.organization_id
    # so the owner branch alone satisfies it and organization A's report comes
    # back while only organization B is open. EctoWellbeingStore's
    # scoped_to_owner_or_tenant/1 has the identical OR, so neither layer
    # constrains the other: this reaches production.
    #
    # Asserted as-is to lock current behaviour. Flipping this to `refute` is
    # the regression test once the boundary is decided - it needs both an
    # application-layer change and a migration replacing the policy, and it
    # turns on a product question (should personal health records follow the
    # member across organizations, or be partitioned per tenant?).
    assert "shoulder" in areas

    as_session(conn, user_id_s, nil, false, fn ->
      Postgrex.query!(conn, "DELETE FROM injury_reports WHERE user_id = $1", [user_id])
    end)

    Postgrex.query!(conn, "DELETE FROM organizations WHERE id = ANY($1)", [[org_a_id, org_b_id]])
    Postgrex.query!(conn, "DELETE FROM users WHERE id = $1", [user_id])
  end
end
