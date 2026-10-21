defmodule MilosTraining.Application.ListWorkoutExecutions do
  alias MilosTraining.Application.JournalComments
  alias MilosTraining.Execution
  alias MilosTraining.Execution.ExecutionStore
  alias MilosTraining.{Organizations, Workouts}

  def call(context, user_id),
    do: ExecutionStore.with_user_context(context, fn -> call(user_id) end)

  def call(user_id) do
    {:ok, user_id |> Execution.list_executions_for_user() |> summarize()}
  end

  def for_coaching(user_id) do
    user_id
    |> Execution.list_executions_for_coaching()
    |> summarize()
  end

  @doc """
  Executions as readers see them: with their Σχόλια and the title, type and
  section names of the workout done. Each workout is read once.
  """
  def summarize(executions) do
    workouts =
      executions
      |> Enum.filter(&(is_binary(&1.organization_id) and is_binary(&1.master_workout_id)))
      |> Enum.uniq_by(&{&1.organization_id, &1.master_workout_id})
      |> Map.new(&{{&1.organization_id, &1.master_workout_id}, fetch_workout(&1)})

    executions
    |> JournalComments.attach("execution")
    |> Enum.map(&attach_workout_summary(&1, workouts))
  end

  defp attach_workout_summary(execution, workouts) do
    case Map.get(workouts, {execution.organization_id, execution.master_workout_id}) do
      nil ->
        Map.merge(execution, %{
          workout_title: "Deleted workout",
          workout_type: nil,
          workout_tags: [],
          workout_source_id: nil,
          exercise_names: [],
          section_scores: attach_section_names(execution.section_scores || [], %{})
        })

      workout ->
        Map.merge(execution, %{
          workout_title: workout.title,
          workout_type: workout.type,
          # ADR-162: what the cross-provider Vault and Πρόοδος group by.
          workout_tags: Map.get(workout, :tags) || [],
          workout_source_id: Map.get(workout, :source_workout_id),
          exercise_names: exercise_names(workout),
          section_scores:
            attach_section_names(execution.section_scores || [], section_name_lookup(workout))
        })
    end
  end

  # The workout belongs to the gym where it was done; the user-scoped history
  # cannot see it without that gym's tenant context. Without one it is
  # unreachable and shows as deleted (ADR-133).
  defp fetch_workout(%{organization_id: organization_id, master_workout_id: workout_id})
       when is_binary(organization_id) do
    with {:ok, context} <-
           Organizations.resolve_system_tenant_context(organization_id, :execution_history, %{
             service: __MODULE__
           }),
         %{} = workout <- Workouts.get_workout(context, workout_id) do
      workout
    else
      _unreachable -> nil
    end
  end

  defp fetch_workout(_execution), do: nil

  defp attach_section_names(section_scores, lookup) do
    Enum.map(section_scores, fn score ->
      Map.put(score, :section_name, Map.get(lookup, score[:section_id] || score["section_id"]))
    end)
  end

  defp exercise_names(workout) do
    for section <- workout.sections || [],
        exercise <- List.wrap(Map.get(section, :exercises)),
        is_map(exercise),
        name = Map.get(exercise, :name),
        is_binary(name),
        uniq: true,
        do: name
  end

  defp section_name_lookup(workout) do
    workout.sections
    |> Enum.map(fn section -> {section.id, section.name} end)
    |> Map.new()
  end
end
