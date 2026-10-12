defmodule MilosTraining.Workouts.ScaleLevelsTenantBackfillMigrationTest do
  @moduledoc """
  ADR-110 / TD-048: the 20261012160000 migration turns the global
  `scale_levels` table into per-organization copies and repoints every
  variation at its own organization's copy.

  The test rolls the migration back inside the sandbox transaction (which
  recreates the global table and points every variation at the shared global
  rows - exactly the pre-migration shape), adds an extra global row, and runs
  it forward again. The sandbox rollback restores the schema afterwards.
  """

  use MilosTraining.DataCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.{Organizations, Workouts}

  @version 20_261_012_160_000
  @migration MilosTraining.Repo.Migrations.ScopeScaleLevelsToOrganizations
  @migration_file "priv/repo/migrations/20261012160000_scope_scale_levels_to_organizations.exs"

  setup_all do
    unless Code.ensure_loaded?(@migration) do
      Code.require_file(Application.app_dir(:milos_training, @migration_file))
    end

    :ok
  end

  test "backfill gives every organization independent copies and remaps variations" do
    {org_a, context_a, workout_a} = tenant_with_workout!("Backfill Gym A")
    {org_b, context_b, workout_b} = tenant_with_workout!("Backfill Gym B")

    migrate!(:down)

    refute column?("scale_levels", "organization_id")

    global_ids = variation_level_ids([org_a.id, org_b.id])
    # Pre-migration shape: both gyms' variations share the same global rows.
    assert global_ids[org_a.id] == global_ids[org_b.id]

    query!("""
    INSERT INTO scale_levels (id, slug, label, sort_order, is_active, inserted_at, updated_at)
    VALUES (gen_random_uuid(), 'competition', 'Competition', 900, true, now(), now())
    """)

    migrate!(:up)

    assert column?("scale_levels", "organization_id")
    assert query!("SELECT count(*) FROM scale_levels WHERE organization_id IS NULL") == [[0]]

    levels_a = org_levels(org_a.id)
    levels_b = org_levels(org_b.id)

    for slug <- ["scaled", "rx", "rx-plus", "competition"] do
      assert Map.has_key?(levels_a, slug)
      assert Map.has_key?(levels_b, slug)
    end

    assert MapSet.disjoint?(MapSet.new(Map.values(levels_a)), MapSet.new(Map.values(levels_b)))

    remapped = variation_level_ids([org_a.id, org_b.id])
    assert remapped[org_a.id] == MapSet.new([levels_a["scaled"], levels_a["rx"]])
    assert remapped[org_b.id] == MapSet.new([levels_b["scaled"], levels_b["rx"]])

    # A variation can no longer point at another organization's level.
    # (Inside a savepoint so the failure does not abort the sandbox transaction.)
    assert_raise Postgrex.Error, ~r/exercise_variations_scale_level_id_fkey/, fn ->
      Repo.transaction(fn ->
        query!(
          """
          UPDATE exercise_variations SET scale_level_id = $1
          WHERE id = (SELECT id FROM exercise_variations WHERE organization_id = $2 LIMIT 1)
          """,
          [Ecto.UUID.dump!(levels_b["rx-plus"]), Ecto.UUID.dump!(org_a.id)]
        )
      end)
    end

    # The copies are independent: renaming A's level leaves B's alone.
    assert {:ok, _} =
             Workouts.replace_scale_levels(context_a, [
               %{slug: "scaled", label: "Foundation", sort_order: 1},
               %{slug: "rx", label: "Prescribed", sort_order: 2}
             ])

    assert Enum.map(Workouts.list_scale_levels(context_b), & &1.label) ==
             ["Scaled", "Rx", "Rx+", "Competition"]

    # Executions store the slug, which resolves against each gym's own copy.
    materialized_a =
      Workouts.materialize_for_scale(Workouts.get_workout(context_a, workout_a.id), "rx")

    materialized_b =
      Workouts.materialize_for_scale(Workouts.get_workout(context_b, workout_b.id), "rx")

    assert materialized_a.scale_level.label == "Prescribed"
    assert materialized_b.scale_level.label == "Rx"
    assert materialized_b.scale_level.id == levels_b["rx"]
    assert first_exercise(materialized_b).prescription_value == 8
  end

  defp tenant_with_workout!(name) do
    {:ok, organization} = Organizations.create_organization(%{name: name})
    admin = admin_fixture()
    context = %{organization_id: organization.id, user_id: admin.id}
    {:ok, _levels} = Workouts.seed_default_scale_levels(context)

    {:ok, workout} =
      Workouts.create_workout(context, admin, %{
        title: "#{name} Grinder",
        type: "crossfit",
        sections: [
          %{
            name: "Main",
            order: 1,
            exercises: [
              %{
                name: "Thrusters",
                order: 1,
                prescription_value: 12,
                prescription_unit: "reps",
                variations: [
                  %{scale_level_slug: "scaled", prescription_value: 6},
                  %{scale_level_slug: "rx", prescription_value: 8}
                ]
              }
            ]
          }
        ]
      })

    {organization, context, workout}
  end

  defp first_exercise(workout), do: workout.sections |> hd() |> Map.fetch!(:exercises) |> hd()

  # `Ecto.Migrator` runs each migration in a Task while the caller holds the
  # migration lock on its own connection, which deadlocks the single sandbox
  # connection. The runner executes the migration body in this process, inside
  # the sandbox transaction, and leaves `schema_migrations` untouched.
  defp migrate!(direction) do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @version,
      @migration,
      :forward,
      direction,
      direction,
      log: false
    )
  end

  defp column?(table, column) do
    query!(
      "SELECT count(*) FROM information_schema.columns WHERE table_name = $1 AND column_name = $2",
      [table, column]
    ) == [[1]]
  end

  defp org_levels(organization_id) do
    "SELECT slug, id FROM scale_levels WHERE organization_id = $1"
    |> query!([Ecto.UUID.dump!(organization_id)])
    |> Map.new(fn [slug, id] -> {slug, Ecto.UUID.load!(id)} end)
  end

  defp variation_level_ids(organization_ids) do
    "SELECT organization_id, scale_level_id FROM exercise_variations WHERE organization_id = ANY($1)"
    |> query!([Enum.map(organization_ids, &Ecto.UUID.dump!/1)])
    |> Enum.group_by(fn [org, _] -> Ecto.UUID.load!(org) end, fn [_, id] ->
      Ecto.UUID.load!(id)
    end)
    |> Map.new(fn {org, ids} -> {org, MapSet.new(ids)} end)
  end

  defp query!(sql, params \\ []), do: Repo.query!(sql, params).rows
end
