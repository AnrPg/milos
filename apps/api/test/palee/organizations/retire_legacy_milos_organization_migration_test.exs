defmodule Palee.Organizations.RetireLegacyMilosOrganizationMigrationTest do
  @moduledoc """
  TD-109: the 20261223110000 migration removes the seeded "Milos Training"
  organization from a database where nobody belongs to it, renames it where
  someone does, and points the RLS fallback at the neutral legacy slug.

  The migration body runs inside the sandbox transaction (see
  `ScaleLevelsTenantBackfillMigrationTest` for why not `Ecto.Migrator`).
  """

  use Palee.DataCase, async: false

  import Palee.TestFixtures

  alias Palee.Organizations

  @version 20_261_223_110_000
  @migration Palee.Repo.Migrations.RetireLegacyMilosOrganization
  @migration_file "priv/repo/migrations/20261223110000_retire_legacy_milos_organization.exs"

  setup_all do
    unless Code.ensure_loaded?(@migration) do
      Code.require_file(Application.app_dir(:palee, @migration_file))
    end

    :ok
  end

  test "a migrated database has no Milos organization and the fallback finds the neutral one" do
    assert slugs(["legacy-milos-training"]) == []

    {:ok, legacy} = Organizations.ensure_legacy_organization_for_migration()
    assert legacy.slug == "legacy-organization"
    assert [[id]] = Repo.query!("SELECT palee_legacy_organization_id()").rows
    assert Ecto.UUID.load!(id) == legacy.id
  end

  test "an empty seeded organization is deleted" do
    seed_milos_organization!()

    migrate!()

    assert slugs(["legacy-milos-training", "legacy-organization"]) == []
  end

  test "a seeded organization with members is renamed, keeping its members" do
    id = seed_milos_organization!()
    member = user_fixture()

    Repo.query!(
      """
      INSERT INTO organization_memberships (id, organization_id, user_id, role, status, joined_at, inserted_at, updated_at)
      VALUES (gen_random_uuid(), $1, $2, 'member', 'active', now(), now(), now())
      """,
      [id, Ecto.UUID.dump!(member.id)]
    )

    migrate!()

    assert slugs(["legacy-milos-training", "legacy-organization"]) == [
             ["legacy-organization", "Legacy organization"]
           ]

    assert [[1]] =
             Repo.query!(
               "SELECT count(*)::int FROM organization_memberships WHERE organization_id = $1",
               [id]
             ).rows
  end

  defp seed_milos_organization! do
    without_rls(fn ->
      %{rows: [[id]]} =
        Repo.query!("""
        INSERT INTO organizations (id, slug, name, status, inserted_at, updated_at)
        VALUES (gen_random_uuid(), 'legacy-milos-training', 'Milos Training', 'active', now(), now())
        RETURNING id
        """)

      id
    end)
  end

  defp slugs(candidates) do
    without_rls(fn ->
      Repo.query!(
        "SELECT slug, name FROM organizations WHERE slug = ANY($1) ORDER BY slug",
        [candidates]
      ).rows
    end)
  end

  # The test role may lack BYPASSRLS; reads and seeds of these rows go around
  # the policies the same way the migration does.
  defp without_rls(fun) do
    tables = ~w(organizations organization_memberships)
    Enum.each(tables, &Repo.query!("ALTER TABLE #{&1} DISABLE ROW LEVEL SECURITY"))
    result = fun.()
    Enum.each(tables, &Repo.query!("ALTER TABLE #{&1} ENABLE ROW LEVEL SECURITY"))
    result
  end

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
end
