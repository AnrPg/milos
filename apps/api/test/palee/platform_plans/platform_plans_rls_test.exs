defmodule Palee.PlatformPlans.RLSTest do
  @moduledoc """
  ADR-170: the plan catalog is readable by anyone and written only by vendors
  or system sessions; an organization's subscription is read by its owners
  and admins only and written by vendors only; the one write an owner may
  cause is `palee_ensure_platform_subscription`, which never changes an
  existing row. The ordinary suite runs as a superuser, so only this
  connection proves it.
  """
  use Palee.RLSCase, async: false

  setup %{conn: conn} do
    {owner_s, owner} = uuid()
    {member_s, member} = uuid()
    {stranger_s, stranger} = uuid()
    {org_s, org} = uuid()
    unique = System.unique_integer([:positive])

    Postgrex.query!(conn, "SELECT set_config('app.invitation_redemption', 'true', false)", [])

    for {id, nick} <- [
          {owner, "rls_plan_owner_#{unique}"},
          {member, "rls_plan_member_#{unique}"},
          {stranger, "rls_plan_stranger_#{unique}"}
        ] do
      Postgrex.query!(
        conn,
        """
        INSERT INTO users (id, nickname, display_nickname, password_hash, role, email, inserted_at, updated_at)
        VALUES ($1, $2::text, $2::text, 'x', 'member', $2::text || '@placeholder.invalid', now(), now())
        """,
        [id, nick]
      )
    end

    Postgrex.query!(
      conn,
      """
      INSERT INTO organizations (id, name, slug, status, provider_kind, inserted_at, updated_at)
      VALUES ($1, $2, $2, 'active', 'coach', now(), now())
      """,
      [org, "rls-plan-#{unique}"]
    )

    for {user_id, role} <- [{owner, "owner"}, {member, "member"}] do
      Postgrex.query!(
        conn,
        """
        INSERT INTO organization_memberships
          (id, organization_id, user_id, role, roles, status, joined_at, inserted_at, updated_at)
        VALUES ($1, $2, $3, $4, ARRAY[$4]::varchar[], 'active', now(), now(), now())
        """,
        [Ecto.UUID.dump!(Ecto.UUID.generate()), org, user_id, role]
      )
    end

    Postgrex.query!(conn, "SELECT set_config('app.invitation_redemption', '', false)", [])

    %{owner: owner_s, member: member_s, stranger: stranger_s, org: org_s, org_bin: org}
  end

  test "an owner starts the default plan of the kind once, and only reads it", ctx do
    %{conn: conn} = ctx

    as_session(conn, ctx.stranger, ctx.org, false, fn ->
      assert_raise Postgrex.Error, ~r/not allowed/, fn ->
        Postgrex.query!(conn, "SELECT palee_ensure_platform_subscription($1)", [ctx.org_bin])
      end
    end)

    as_session(conn, ctx.owner, ctx.org, false, fn ->
      Postgrex.query!(conn, "SELECT palee_ensure_platform_subscription($1)", [ctx.org_bin])
      # A second call never changes the row.
      Postgrex.query!(conn, "SELECT palee_ensure_platform_subscription($1)", [ctx.org_bin])

      assert [["solo_coach", "trialing", true]] == subscription(conn, ctx.org_bin)

      %{num_rows: updated} =
        Postgrex.query!(
          conn,
          "UPDATE organization_platform_subscriptions SET status = 'comped' WHERE organization_id = $1",
          [ctx.org_bin]
        )

      assert updated == 0

      %{num_rows: deleted} =
        Postgrex.query!(
          conn,
          "DELETE FROM organization_platform_subscriptions WHERE organization_id = $1",
          [ctx.org_bin]
        )

      assert deleted == 0
    end)

    as_session(conn, ctx.member, ctx.org, false, fn ->
      assert [] == subscription(conn, ctx.org_bin)
    end)

    as_session(conn, ctx.stranger, ctx.org, false, fn ->
      assert [] == subscription(conn, ctx.org_bin)
    end)
  end

  test "anyone reads the catalog; only vendors or system sessions change it", ctx do
    %{conn: conn} = ctx

    as_session(conn, ctx.stranger, nil, false, fn ->
      %{rows: rows} =
        Postgrex.query!(conn, "SELECT code FROM platform_plans WHERE code = 'solo_coach'", [])

      assert rows == [["solo_coach"]]

      %{num_rows: updated} =
        Postgrex.query!(
          conn,
          "UPDATE platform_plans SET monthly_price_cents = 0 WHERE code = 'solo_coach'",
          []
        )

      assert updated == 0
    end)
  end

  defp subscription(conn, org) do
    %{rows: rows} =
      Postgrex.query!(
        conn,
        """
        SELECT plan_code, status, trial_ends_at > now()
        FROM organization_platform_subscriptions WHERE organization_id = $1
        """,
        [org]
      )

    rows
  end
end
