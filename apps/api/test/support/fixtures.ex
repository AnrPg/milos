defmodule Palee.TestFixtures do
  alias Palee.{Identity, Organizations, Scheduling, Workouts}

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

  @doc """
  ADR-193 §2 (amended 2026-10-25): accounts are public by default; this makes
  one private, so following it is a request. Runs outside any acting user.
  """
  def private_account!(%{id: user_id} = user) do
    Palee.Repo.query!(
      """
      INSERT INTO community_social_settings (user_id, private_account, inserted_at, updated_at)
      VALUES ($1, true, now(), now())
      ON CONFLICT (user_id) DO UPDATE SET private_account = true, updated_at = now()
      """,
      [Ecto.UUID.dump!(user_id)]
    )

    user
  end

  def admin_fixture(attrs \\ %{}) do
    user = user_fixture(Map.put(attrs, :role, :member))
    {:ok, admin} = Identity.update_role(user, :admin)
    admin
  end

  @doc """
  ADR-184: lifts the demo gate of a business opened in demo mode (a coach
  practice, a business sign-up) without the activation link, for tests that
  exercise what an active business does. Runs outside any acting user, which
  the activation guard trigger allows.
  """
  def activate_business!(organization_id) do
    Palee.Repo.query!(
      "UPDATE organizations SET activation = 'active', activated_at = now() WHERE id = $1",
      [Ecto.UUID.dump!(organization_id)]
    )

    organization_id
  end

  def workout_fixture(admin, attrs \\ %{}) do
    context =
      Map.get(attrs, :tenant_context) || ambient_tenant_context() || legacy_tenant_context()

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
      |> Map.delete(:tenant_context)

    {:ok, workout} = Workouts.create_workout(context, admin, params)
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

    # A new database seeds no class types (the pre-tenancy defaults left with
    # the retired legacy organization), so the first slot brings its own.
    default_class_type =
      List.first(Scheduling.list_class_types(context)) ||
        class_type_fixture(%{tenant_context: context, name: "CrossFit"})

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

    {:ok, slot} = Palee.Scheduling.create_slot(context, params)
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

  # Many tests set the RLS session GUCs (app.organization_id/app.user_id)
  # directly before calling this fixture instead of threading a context
  # struct through. Honor that ambient scope when present so the created
  # workout lands in the organization the test actually set up, instead of
  # always defaulting to the legacy org.
  defp ambient_tenant_context do
    case Palee.Infrastructure.Tenancy.RepoContext.current_setting("app.organization_id") do
      nil -> nil
      organization_id -> system_tenant_context(organization_id, :workout_fixture_ambient)
    end
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
