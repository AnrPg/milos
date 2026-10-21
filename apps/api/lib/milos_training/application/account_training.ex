defmodule MilosTraining.Application.AccountTraining do
  @moduledoc """
  The account-level training read model (ADR-150, ADR-162): every workout
  the member did, at every provider, freeform or from a device, read in the
  member's personal session (row security admits their own rows across
  organizations, the same predicate the journal feed uses). Each attempt
  carries its canonical workout identity (`WorkoutIdentity`) and its
  source label (`EntrySource`), so the Vault, Πρόοδος and history can group
  and filter across providers.
  """

  alias MilosTraining.Application.ListWorkoutExecutions
  alias MilosTraining.Execution.ExecutionStore
  alias MilosTraining.{Execution, Journal, Organizations}

  @log_limit 2_000

  @doc "Providers, their directory, and the member's executions (all statuses)."
  def load(%{user_id: user_id} = context) do
    providers = Organizations.list_my_providers(context)
    directory = Organizations.provider_directory(providers)

    {:ok, executions} = ListWorkoutExecutions.call(context, user_id)

    logs =
      ExecutionStore.with_user_context(context, fn ->
        Execution.list_training_log_items(user_id, :none, @log_limit, :owner)
      end)

    %{
      providers: providers,
      directory: directory,
      executions: Enum.map(executions, &execution(&1, directory)),
      logs: Enum.map(logs, &log(&1, directory))
    }
  end

  @doc "Completed executions and logged entries as uniform attempts, newest first."
  def attempts(%{executions: executions, logs: logs}) do
    (Enum.filter(executions, &(&1.status == "completed" and &1.completed_at_utc)) ++ logs)
    |> Enum.map(&attempt/1)
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
  end

  defp execution(execution, directory) do
    source = Journal.entry_source(execution.organization_id, nil, directory)

    Map.merge(execution, %{
      status: to_string(execution.status),
      source_label: source,
      section_scores: Enum.map(execution.section_scores || [], &section_key/1),
      workout_key:
        Execution.workout_identity(%{
          title: execution.workout_title,
          type: execution.workout_type,
          tags: Map.get(execution, :workout_tags, []),
          source_workout_id: Map.get(execution, :workout_source_id)
        }) || fallback_key(execution)
    })
  end

  defp log(entry, directory) do
    device = if Journal.device_source?(entry.source_type), do: entry.source_type
    source = Journal.entry_source(entry.organization_id, device, directory)

    Map.merge(entry, %{
      source_label: source,
      workout_key:
        Execution.workout_identity(%{title: entry.title, type: entry.workout_type}) ||
          fallback_key(entry)
    })
  end

  defp attempt(%{performed_at_utc: at} = entry) do
    %{
      kind: "training_log",
      id: entry.id,
      key: entry.workout_key,
      title: entry.title,
      type: entry.workout_type,
      at: at,
      on: DateTime.to_date(at),
      tz: entry.performed_at_tz,
      source: entry.source_label,
      source_token: token(entry.source_label),
      exercise_names: names(entry.performed_exercises),
      scale_level_slug: entry.scale_level_slug,
      duration_seconds: entry.duration_seconds,
      scores: scores(entry.section_scores)
    }
  end

  defp attempt(execution) do
    %{
      kind: "execution",
      id: execution.id,
      key: execution.workout_key,
      title: execution.workout_title,
      type: execution.workout_type && to_string(execution.workout_type),
      at: execution.completed_at_utc,
      on: DateTime.to_date(execution.completed_at_utc),
      tz: execution.completed_at_tz,
      source: execution.source_label,
      source_token: token(execution.source_label),
      exercise_names: Map.get(execution, :exercise_names, []),
      scale_level_slug: execution.scale_level_slug,
      duration_seconds: div(execution.total_elapsed_ms || 0, 1000),
      scores: scores(execution.section_scores)
    }
  end

  # Sections of one workout identity match across providers by name.
  defp section_key(score) do
    name = field(score, :section_name)

    key =
      if is_binary(name) and name != "",
        do: "name:" <> String.downcase(String.trim(name)),
        else: field(score, :section_id)

    Map.put(score, :section_key, key)
  end

  @doc "The filter token of a source label."
  def token(%{kind: "organization", organization_id: id}), do: id
  def token(%{kind: kind}), do: kind

  defp fallback_key(%{master_workout_id: id}) when is_binary(id), do: "workout:" <> id
  defp fallback_key(%{id: id}), do: "attempt:" <> id

  defp names(exercises) do
    for exercise <- List.wrap(exercises),
        is_map(exercise),
        name = Map.get(exercise, :name) || Map.get(exercise, "name"),
        is_binary(name),
        uniq: true,
        do: name
  end

  defp scores(scores) do
    scores
    |> List.wrap()
    |> Enum.map(fn score ->
      %{
        section_id: field(score, :section_id),
        section_name: field(score, :section_name),
        value: field(score, :value),
        unit: field(score, :unit)
      }
    end)
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, to_string(key)))
end
