defmodule Palee.Pantheon.PRProvenanceBackfillMigrationTest do
  @moduledoc """
  ADR-132 / TD-091: the 20261016120000 data migration gives legacy PRs (no
  organization provenance) the gym they were set in, only where it is
  unambiguous: one gym among the owner's executions around `beaten_on`, or -
  with no execution evidence - the owner's only membership, joined before the
  PR was recorded. Everything else stays personal, and rows that already have
  provenance are never touched.

  The migration body runs inside the sandbox transaction (see
  `ScaleLevelsTenantBackfillMigrationTest` for why not `Ecto.Migrator`).
  """

  use Palee.DataCase, async: false

  import Palee.TestFixtures

  alias Palee.Application.{CreatePR, UpdatePR}
  alias Palee.Identity.UserContext
  alias Palee.Organizations

  @version 20_261_016_120_000
  @migration Palee.Repo.Migrations.BackfillLegacyPrProvenance
  @migration_file "priv/repo/migrations/20261016120000_backfill_legacy_pr_provenance.exs"

  setup_all do
    unless Code.ensure_loaded?(@migration) do
      Code.require_file(Application.app_dir(:palee, @migration_file))
    end

    :ok
  end

  setup do
    {:ok, gym_a} = Organizations.create_organization(%{name: "Backfill PR Gym A"})
    {:ok, gym_b} = Organizations.create_organization(%{name: "Backfill PR Gym B"})
    %{gym_a: gym_a, gym_b: gym_b}
  end

  test "a single-gym member's legacy PR takes that gym, and its history follows", ctx do
    member = user_fixture()
    add!(ctx.gym_a, member, days_ago(30))
    pr = legacy_pr!(member, "Back squat")

    {:ok, _improved} =
      UpdatePR.call(UserContext.new(member), pr.id, %{
        "current_score" => 140,
        "beaten_on" => Date.to_iso8601(Date.utc_today())
      })

    assert history_orgs(pr.id) == [nil]

    migrate!()

    assert provenance(pr.id) == ctx.gym_a.id
    assert history_orgs(pr.id) == [ctx.gym_a.id]
  end

  test "executions around the PR date in exactly one gym decide between memberships", ctx do
    member = user_fixture()
    add!(ctx.gym_a, member, days_ago(30))
    add!(ctx.gym_b, member, days_ago(30))
    pr = legacy_pr!(member, "Snatch")
    execution!(member, ctx.gym_b, DateTime.utc_now())

    migrate!()

    assert provenance(pr.id) == ctx.gym_b.id
  end

  test "ambiguous evidence leaves the PR personal", ctx do
    two_gyms = user_fixture()
    add!(ctx.gym_a, two_gyms, days_ago(30))
    add!(ctx.gym_b, two_gyms, days_ago(30))
    no_evidence = legacy_pr!(two_gyms, "Deadlift")

    both_gyms = user_fixture()
    add!(ctx.gym_a, both_gyms, days_ago(30))
    add!(ctx.gym_b, both_gyms, days_ago(30))
    split = legacy_pr!(both_gyms, "Clean")
    execution!(both_gyms, ctx.gym_a, DateTime.utc_now())
    execution!(both_gyms, ctx.gym_b, DateTime.utc_now())

    late_joiner = user_fixture()
    add!(ctx.gym_a, late_joiner, DateTime.utc_now())
    before_joining = legacy_pr!(late_joiner, "Marathon")
    set_inserted_at!(before_joining.id, days_ago(10))

    no_gym = user_fixture()
    lone = legacy_pr!(no_gym, "Mile")

    migrate!()

    assert provenance(no_evidence.id) == nil
    assert provenance(split.id) == nil
    assert provenance(before_joining.id) == nil
    assert provenance(lone.id) == nil
  end

  test "existing provenance is never changed and re-running is a no-op", ctx do
    member = user_fixture()
    add!(ctx.gym_a, member, days_ago(30))
    add!(ctx.gym_b, member, days_ago(30))

    {:ok, chosen} =
      CreatePR.call(UserContext.new(member), pr_params("Front squat", ctx.gym_a.slug))

    legacy = legacy_pr!(member, "Push press")
    execution!(member, ctx.gym_b, DateTime.utc_now())

    migrate!()
    migrate!()

    assert provenance(chosen.id) == ctx.gym_a.id
    assert provenance(legacy.id) == ctx.gym_b.id
  end

  defp legacy_pr!(user, name) do
    {:ok, pr} = CreatePR.call(UserContext.new(user), pr_params(name, nil))
    assert pr.organization_id == nil
    pr
  end

  defp pr_params(name, slug) do
    %{
      "name" => name,
      "current_score" => 120,
      "unit" => "kg",
      "beaten_on" => Date.to_iso8601(Date.utc_today()),
      "organization_slug" => slug
    }
  end

  defp add!(organization, user, joined_at) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: :member,
        status: :active,
        joined_at: joined_at
      })

    membership
  end

  defp execution!(user, organization, started_at) do
    query!(
      """
      INSERT INTO workout_executions (id, user_id, organization_id, started_at_utc, inserted_at)
      VALUES (gen_random_uuid(), $1, $2, $3, now())
      """,
      [Ecto.UUID.dump!(user.id), Ecto.UUID.dump!(organization.id), started_at]
    )
  end

  defp set_inserted_at!(pr_id, at) do
    query!("UPDATE user_pr_records SET inserted_at = $2 WHERE id = $1", [
      Ecto.UUID.dump!(pr_id),
      at
    ])
  end

  defp provenance(pr_id) do
    [[org]] = query!("SELECT organization_id FROM user_pr_records WHERE id = $1", [uuid(pr_id)])
    load(org)
  end

  defp history_orgs(pr_id) do
    "SELECT organization_id FROM user_pr_history WHERE pr_record_id = $1"
    |> query!([uuid(pr_id)])
    |> Enum.map(fn [org] -> load(org) end)
  end

  defp days_ago(days), do: DateTime.add(DateTime.utc_now(), -days * 86_400, :second)
  defp uuid(id), do: Ecto.UUID.dump!(id)
  defp load(nil), do: nil
  defp load(org), do: Ecto.UUID.load!(org)

  defp migrate! do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @version,
      @migration,
      :forward,
      :up,
      :up,
      log: false
    )
  end

  defp query!(sql, params), do: Repo.query!(sql, params).rows
end
