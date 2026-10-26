defmodule Palee.Spaces.SpacesFromCleaningAreasMigrationTest do
  @moduledoc """
  ADR-202: the 20261222100000 migration turns the cleaning areas into
  spaces in place, so every area keeps its id, branch and tasks and every
  cleaning entry still points at it.

  The test rolls both ADR-202 migrations back inside the sandbox transaction
  (the pre-ADR-202 shape), writes areas and entries the way ADR-102 did, and
  runs them forward again. The sandbox rollback restores the schema.
  """

  use Palee.DataCase, async: false

  import Palee.TestFixtures

  alias Palee.Application.CleaningLog
  alias Palee.{Organizations, Spaces}

  @migrations [
    {20_261_222_100_000, Palee.Repo.Migrations.SpacesFromHousekeepingAreas,
     "priv/repo/migrations/20261222100000_spaces_from_housekeeping_areas.exs"},
    {20_261_222_110_000, Palee.Repo.Migrations.ClassSpacesCleaningSchedulesAndPlacements,
     "priv/repo/migrations/20261222110000_class_spaces_cleaning_schedules_and_placements.exs"}
  ]

  setup_all do
    for {_version, module, file} <- @migrations, not Code.ensure_loaded?(module) do
      Code.require_file(Application.app_dir(:palee, file))
    end

    :ok
  end

  test "every cleaning area becomes a space with its tasks and its log" do
    {:ok, organization} = Organizations.create_organization(%{name: "Area Gym"})
    janitor = user_fixture()
    org = Ecto.UUID.dump!(organization.id)

    for {version, module, _file} <- Enum.reverse(@migrations),
        do: migrate!(version, module, :down)

    assert table?("housekeeping_areas")
    refute table?("spaces")

    area_id = Ecto.UUID.generate()
    archived_id = Ecto.UUID.generate()

    query!(
      """
      INSERT INTO housekeeping_areas (id, organization_id, name, tasks, archived_at, inserted_at, updated_at)
      VALUES ($1, $2, 'Showers', '{Floors,Mirrors}', NULL, now(), now()),
             ($3, $2, 'Old sauna', '{}', now(), now(), now())
      """,
      [Ecto.UUID.dump!(area_id), org, Ecto.UUID.dump!(archived_id)]
    )

    query!(
      """
      INSERT INTO housekeeping_entries (id, organization_id, area_id, user_id, started_at, finished_at, tasks_done, inserted_at, updated_at)
      VALUES (gen_random_uuid(), $1, $2, $3, now() - interval '1 hour', now() - interval '30 minutes', '{Floors}', now(), now())
      """,
      [org, Ecto.UUID.dump!(area_id), Ecto.UUID.dump!(janitor.id)]
    )

    for {version, module, _file} <- @migrations, do: migrate!(version, module, :up)

    refute table?("housekeeping_areas")
    context = %{organization_id: organization.id, user_id: janitor.id}

    assert %{name: "Showers", tasks: ["Floors", "Mirrors"], description: nil, area: nil} =
             Spaces.get_space(context, area_id)

    assert %{name: "Old sauna", archived_at: %DateTime{}} = Spaces.get_space(context, archived_id)

    # The cleaning log reads the same rows, with the entry still attached.
    assert [%{id: ^area_id, last_cleaned_at: %DateTime{}}] = CleaningLog.areas(context)

    # Entries cannot point at a space of another gym, nor at a missing one.
    assert_raise Postgrex.Error, ~r/housekeeping_entries_area_fkey/, fn ->
      Repo.transaction(fn ->
        query!(
          """
          INSERT INTO housekeeping_entries (id, organization_id, area_id, started_at, tasks_done, inserted_at, updated_at)
          VALUES (gen_random_uuid(), $1, gen_random_uuid(), now(), '{}', now(), now())
          """,
          [org]
        )
      end)
    end

    assert {:ok, %{id: _}} = Spaces.create_space(context, %{name: "Cardio"})
  end

  # See ScaleLevelsTenantBackfillMigrationTest: the runner executes the
  # migration in this process, inside the sandbox transaction.
  defp migrate!(version, module, direction) do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      version,
      module,
      :forward,
      direction,
      direction,
      log: false
    )
  end

  defp table?(name) do
    query!("SELECT count(*) FROM information_schema.tables WHERE table_name = $1", [name]) ==
      [[1]]
  end

  defp query!(sql, params), do: Repo.query!(sql, params).rows
end
