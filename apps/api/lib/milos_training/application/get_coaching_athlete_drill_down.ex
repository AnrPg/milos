defmodule MilosTraining.Application.GetCoachingAthleteDrillDown do
  @moduledoc false

  alias MilosTraining.Application.ListWorkoutExecutions
  alias MilosTraining.Coaching
  alias MilosTraining.Coaching.Domain.AthleteDrillDown
  alias MilosTraining.{Identity, Organizations}
  alias MilosTraining.Messaging
  alias MilosTraining.Workouts

  def call(athlete_id, params \\ %{}) do
    with %{role: :athlete} = athlete <- Identity.find_by_id(athlete_id),
         {:ok, executions} <- ListWorkoutExecutions.call(athlete_id) do
      {start_date, end_date} = assignment_window(params)

      assignments = Workouts.list_assigned_workouts_for_athlete(athlete_id, start_date, end_date)
      coaching_messages = fetch_coaching_messages(athlete_id)

      {:ok,
       %{
         drill_down:
           AthleteDrillDown.build(
             athlete,
             assignments,
             executions,
             coaching_messages,
             Date.utc_today()
           )
       }}
    else
      nil -> {:error, :not_found}
      %{role: _other_role} -> {:error, :forbidden}
      error -> error
    end
  end

  def call(%{organization_id: organization_id} = context, athlete_id, params)
      when is_binary(organization_id) do
    Coaching.with_tenant_context(context, fn ->
      with %{role: :athlete} = athlete <- Identity.find_by_id(athlete_id),
           true <- active_athlete_membership?(athlete_id, organization_id) do
        {start_date, end_date} = assignment_window(params)

        assignments =
          Workouts.list_assigned_workouts_for_athlete(athlete_id, start_date, end_date)

        executions = ListWorkoutExecutions.for_coaching(athlete_id)
        coaching_messages = Messaging.list_recent_coaching_notes_for_organization(athlete_id, 50)

        {:ok,
         %{
           drill_down:
             AthleteDrillDown.build(
               athlete,
               assignments,
               executions,
               coaching_messages,
               Date.utc_today()
             )
         }}
      else
        nil -> {:error, :not_found}
        %{role: _other_role} -> {:error, :forbidden}
        false -> {:error, :not_found}
        error -> error
      end
    end)
  end

  defp fetch_coaching_messages(athlete_id) do
    Messaging.list_recent_coaching_notes(athlete_id, 50)
  end

  defp active_athlete_membership?(athlete_id, organization_id) do
    Enum.any?(Organizations.list_memberships(athlete_id), fn %{membership: membership} ->
      membership.organization_id == organization_id and membership.role == :athlete and
        membership.status == :active
    end)
  end

  defp assignment_window(params) do
    today = Date.utc_today()

    start_date =
      params
      |> field(:start_date)
      |> parse_date(Date.add(today, -30))

    end_date =
      params
      |> field(:end_date)
      |> parse_date(Date.add(today, 30))

    {start_date, end_date}
  end

  defp parse_date(%Date{} = date, _default), do: date

  defp parse_date(value, default) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> default
    end
  end

  defp parse_date(_value, default), do: default

  defp field(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp field(_map, _key), do: nil
end
