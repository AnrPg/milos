defmodule MilosTraining.CoachingTest do
  use MilosTraining.DataCase

  alias MilosTraining.{Coaching, Execution.WorkoutExecution, Organizations, TestFixtures}

  test "coaching aggregates separate active and inactive athletes" do
    owner = TestFixtures.user_fixture()
    active_athlete = TestFixtures.user_fixture(%{role: :athlete})
    inactive_athlete = TestFixtures.user_fixture(%{role: :athlete})
    {:ok, organization} = Organizations.create_organization(%{name: "Coaching Members"})

    for {user, role} <- [
          {owner, :owner},
          {active_athlete, :athlete},
          {inactive_athlete, :athlete}
        ] do
      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    completed_at = DateTime.add(DateTime.utc_now(), -7, :day)

    %WorkoutExecution{organization_id: organization.id}
    |> WorkoutExecution.start_changeset(%{
      user_id: active_athlete.id,
      source: :self_selected,
      status: :completed,
      started_at_utc: DateTime.add(completed_at, -1800, :second),
      started_at_tz: "UTC"
    })
    |> Ecto.Changeset.put_change(:completed_at_utc, completed_at)
    |> Ecto.Changeset.put_change(:completed_at_tz, "UTC")
    |> Repo.insert!()

    assert :ok = Coaching.refresh_aggregates()
    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    aggregates = Coaching.get_aggregates(context)

    assert aggregates.active_athlete_count == 1
    assert aggregates.inactive_athlete_count == 1
    assert aggregates.completed_workouts_this_week >= 0
    refute aggregates.active_athlete_count + aggregates.inactive_athlete_count < 2
    refute inactive_athlete.id == active_athlete.id
  end

  test "coaching aggregates only include the active tenant's athletes and provenance" do
    admin_a = TestFixtures.user_fixture()
    admin_b = TestFixtures.user_fixture()
    athlete_a = TestFixtures.user_fixture(%{role: :athlete})
    athlete_b = TestFixtures.user_fixture(%{role: :athlete})

    {:ok, organization_a} = Organizations.create_organization(%{name: "Coaching Alpha"})
    {:ok, organization_b} = Organizations.create_organization(%{name: "Coaching Beta"})

    for {organization, user, role} <- [
          {organization_a, admin_a, :owner},
          {organization_a, athlete_a, :athlete},
          {organization_b, admin_b, :owner},
          {organization_b, athlete_b, :athlete}
        ] do
      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    completed_at = DateTime.add(DateTime.utc_now(), -10, :minute)

    %WorkoutExecution{organization_id: organization_a.id}
    |> WorkoutExecution.start_changeset(%{
      user_id: athlete_a.id,
      source: :assigned,
      status: :completed,
      started_at_utc: DateTime.add(completed_at, -1_800, :second),
      started_at_tz: "UTC"
    })
    |> Ecto.Changeset.put_change(:completed_at_utc, completed_at)
    |> Ecto.Changeset.put_change(:completed_at_tz, "UTC")
    |> Repo.insert!()

    assert :ok = Coaching.refresh_aggregates()

    {:ok, context_a} = Organizations.resolve_tenant_context(admin_a, organization_a.slug)
    {:ok, context_b} = Organizations.resolve_tenant_context(admin_b, organization_b.slug)

    assert %{active_athlete_count: 1, completed_workouts_this_week: 1} =
             Coaching.get_aggregates(context_a)

    assert %{active_athlete_count: 0, inactive_athlete_count: 1, completed_workouts_this_week: 0} =
             Coaching.get_aggregates(context_b)
  end
end
