defmodule Palee.Application.GetAssignedWorkoutWeek do
  alias Palee.Application.{CoveringBranches, Seasons}
  alias Palee.{Identity, Workouts}

  def call(context, user, params) do
    with {:ok, start_date} <- parse_start_date(params) do
      end_date = Date.add(start_date, 6)

      assignments =
        case context.role do
          role when role in [:owner, :admin, :coach] ->
            Workouts.list_assigned_workouts_for_admin(context, start_date, end_date)
            |> at_branches(context, params)
            |> attach_athletes()

          # ADR-125: members see the personal workouts and class variants
          # addressed to them, exactly like athletes.
          role when role in [:athlete, :member] ->
            Workouts.list_assigned_workouts_for_athlete(context, user.id, start_date, end_date)
            |> strip_admin_fields()

          _role ->
            []
        end

      {:ok,
       %{
         start_date: Date.to_iso8601(start_date),
         end_date: Date.to_iso8601(end_date),
         # ADR-167: a season's workouts carry the season's title.
         assignments: Seasons.label_assignments(context, assignments)
       }}
    end
  end

  def call(_user, _params), do: {:error, :organization_context_required}

  # ADR-186 §7/§8: staff see the programmes valid at one of their branches,
  # narrowed further by the page's branch filter.
  defp at_branches(assignments, context, params) do
    visible = CoveringBranches.visible(context, assignments, &CoveringBranches.of_row/1)

    case Palee.Organizations.requested_location_ids(params) do
      [] ->
        visible

      ids ->
        Enum.filter(
          visible,
          &Palee.Organizations.covering_visible?(ids, CoveringBranches.of_row(&1))
        )
    end
  end

  defp parse_start_date(params) do
    case Map.get(params, "start_date") || Map.get(params, :start_date) do
      nil ->
        {:ok, Date.utc_today() |> Date.beginning_of_week(:monday)}

      "" ->
        {:ok, Date.utc_today() |> Date.beginning_of_week(:monday)}

      value ->
        case Date.from_iso8601(value) do
          {:ok, date} -> {:ok, date}
          {:error, _reason} -> {:error, :bad_request}
        end
    end
  end

  defp attach_athletes(assignments) do
    athletes_by_id =
      assignments
      |> Enum.flat_map(&Map.get(&1, :athlete_ids, []))
      |> Enum.uniq()
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, %{id: &1.id, nickname: &1.nickname, role: to_string(&1.role)}})

    Enum.map(assignments, fn assignment ->
      athletes =
        assignment
        |> Map.get(:athlete_ids, [])
        |> Enum.map(&Map.get(athletes_by_id, &1))
        |> Enum.reject(&is_nil/1)

      Map.put(assignment, :athletes, athletes)
    end)
  end

  defp strip_admin_fields(assignments) do
    Enum.map(assignments, &Map.drop(&1, [:athlete_ids]))
  end
end
