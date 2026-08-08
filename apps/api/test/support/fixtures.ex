defmodule MilosTraining.TestFixtures do
  alias MilosTraining.{Identity, Organizations, Scheduling, Workouts}

  def user_fixture(attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    params =
      %{
        nickname: "user_#{unique}",
        password: "S3cur3P@ss!42",
        role: :member,
        email: "user_#{unique}@placeholder.invalid"
      }
      |> Map.merge(attrs)

    {:ok, user} = Identity.register(params)
    user
  end

  def admin_fixture(attrs \\ %{}) do
    user = user_fixture(Map.put(attrs, :role, :member))
    {:ok, admin} = Identity.update_role(user, :admin)
    admin
  end

  def workout_fixture(admin, attrs \\ %{}) do
    params =
      %{
        title: "Workout #{System.unique_integer([:positive])}",
        type: :crossfit,
        sections: [
          %{
            name: "Main Set",
            order: 1,
            scoreable: false,
            exercises: [
              %{
                name: "Air Squats",
                order: 1,
                sets: 3,
                prescription_value: 10,
                prescription_unit: "reps"
              }
            ]
          }
        ]
      }
      |> deep_merge(attrs)

    {:ok, workout} = Workouts.create_workout(admin, params)
    workout
  end

  def class_type_fixture(attrs \\ %{}) do
    unique = System.unique_integer([:positive])
    context = Map.get(attrs, :tenant_context) || legacy_tenant_context()

    params = %{
      name: Map.get(attrs, :name, "Class Type #{unique}"),
      slug: Map.get(attrs, :slug, "class-type-#{unique}"),
      sort_order: Map.get(attrs, :sort_order, unique)
    }

    {:ok, class_type} = Scheduling.create_class_type(context, params)
    class_type
  end

  def slot_fixture(workout, attrs \\ %{}) do
    context = Map.get(attrs, :tenant_context) || workout_tenant_context(workout)
    default_class_type = Scheduling.list_class_types(context) |> List.first()

    params =
      %{
        master_workout_id: workout.id,
        class_type_id: default_class_type.id,
        scheduled_at:
          DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), 3600, :second),
        capacity: 10,
        auto_approve: false,
        booking_timeout_minutes: 60
      }
      |> Map.merge(attrs)
      |> Map.delete(:tenant_context)

    {:ok, slot} = MilosTraining.Scheduling.create_slot(context, params)
    slot
  end

  defp workout_tenant_context(%{organization_id: organization_id})
       when is_binary(organization_id),
       do: system_tenant_context(organization_id, :workout_fixture)

  defp workout_tenant_context(_workout), do: legacy_tenant_context()

  defp legacy_tenant_context do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    system_tenant_context(organization.id, :legacy_test_fixture)
  end

  defp system_tenant_context(organization_id, source) do
    {:ok, context} =
      Organizations.resolve_system_tenant_context(organization_id, source, %{service: __MODULE__})

    context
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value) do
        deep_merge(left_value, right_value)
      else
        right_value
      end
    end)
  end
end
