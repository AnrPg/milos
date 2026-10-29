defmodule Palee.Workouts.Domain.PlanAuthoringGuard do
  @moduledoc """
  ADR-270: a workout written in the structured WOD editor keeps its plan
  until the coach deliberately writes it another way. Pure.

  The plan is the source of truth (`workout_sections.plan`); the legacy
  editors only see its materialised exercises. A save from one of them would
  publish those rows as the workout and drop every plan, so it is refused
  with `{:error, :structured_plan_mode_change}`:

  * a Quick Text (DSL) publish, which always writes `quick_text`;
  * a save in the legacy structured editor (`structured`), or one that
    names no mode and carries sections without plans.

  The editor's own toggle stays open: a save that names `structured_plan`
  again, or a text mode (`free_text`, `sectioned_text`) the coach switched
  to on purpose, goes through.
  """

  @plan_mode "structured_plan"
  @deliberate_modes ~w(structured_plan free_text sectioned_text)

  @doc "Whether a workout read model (or its draft) is a structured plan."
  @spec plan_workout?(term()) :: boolean()
  def plan_workout?(%{} = workout) do
    mode(workout) == @plan_mode or mode(field(workout, :draft_data)) == @plan_mode
  end

  def plan_workout?(_workout), do: false

  @doc """
  `:ok`, or `{:error, :structured_plan_mode_change}` when saving `params`
  over `current` would drop its plan (see the module doc).
  """
  @spec check_save(term(), map()) :: :ok | {:error, :structured_plan_mode_change}
  def check_save(current, %{} = params) do
    cond do
      not plan_workout?(current) -> :ok
      mode(params) in @deliberate_modes -> :ok
      is_nil(mode(params)) and plans_kept?(params) -> :ok
      true -> {:error, :structured_plan_mode_change}
    end
  end

  def check_save(_current, _params), do: :ok

  @doc "`:ok`, or the error when a Quick Text publish would replace a plan workout."
  @spec check_quick_text(term()) :: :ok | {:error, :structured_plan_mode_change}
  def check_quick_text(current),
    do: if(plan_workout?(current), do: {:error, :structured_plan_mode_change}, else: :ok)

  # A save without a mode keeps the stored one; it may only drop no plan.
  defp plans_kept?(params) do
    case field(params, :sections) do
      sections when is_list(sections) -> Enum.all?(sections, &is_map(field(&1, :plan)))
      _none -> true
    end
  end

  defp mode(%{} = map) do
    case field(map, :authoring_mode) do
      nil -> nil
      mode -> to_string(mode)
    end
  end

  defp mode(_map), do: nil

  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(_map, _key), do: nil
end
