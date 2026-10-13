defmodule MilosTraining.Organizations.Domain.OnboardingChecklist do
  @moduledoc """
  The tenant admin's first-run checklist.

  Progress combines what the organization has actually set up (signals such as
  "has a membership package", computed by the caller from other contexts) with
  what the admin told us (a step marked done or skipped, the popup dismissed,
  the product tour finished). Only the admin's choices are persisted, under
  `organization_settings.settings["onboarding"]`, so the checklist can be
  resumed at any time and never regresses when data is later removed.
  """

  @settings_key "onboarding"
  @steps ~w(settings classes packages workout invite tour)
  @actions ~w(complete skip reopen dismiss restore tour_completed)

  def settings_key, do: @settings_key
  def steps, do: @steps

  def default_state,
    do: %{"completed" => [], "skipped" => [], "dismissed_at" => nil, "tour_completed_at" => nil}

  @doc "Reads the stored state from the organization settings map."
  def from_settings(settings) when is_map(settings) do
    case Map.get(settings, @settings_key) do
      %{} = stored ->
        %{
          "completed" => known_steps(Map.get(stored, "completed")),
          "skipped" => known_steps(Map.get(stored, "skipped")),
          "dismissed_at" => string_or_nil(Map.get(stored, "dismissed_at")),
          "tour_completed_at" => string_or_nil(Map.get(stored, "tour_completed_at"))
        }

      _missing ->
        default_state()
    end
  end

  def from_settings(_settings), do: default_state()

  @doc """
  Builds the checklist view. `signals` maps step ids to booleans that say the
  step is already satisfied by real data, e.g. `%{"packages" => true}`.
  """
  def build(state, signals) when is_map(state) and is_map(signals) do
    steps =
      Enum.map(@steps, fn step ->
        auto = step_signal(step, state, signals)
        completed = auto or step in state["completed"]
        skipped = not completed and step in state["skipped"]

        %{"id" => step, "done" => completed, "auto" => auto, "skipped" => skipped}
      end)

    resolved = Enum.count(steps, &(&1["done"] or &1["skipped"]))

    %{
      "steps" => steps,
      "completed_count" => Enum.count(steps, & &1["done"]),
      "total" => length(@steps),
      "finished" => resolved == length(@steps),
      "dismissed" => not is_nil(state["dismissed_at"]),
      "tour_completed" => not is_nil(state["tour_completed_at"])
    }
  end

  @doc "Applies an admin action. Returns `{:ok, new_state}` or an error."
  def apply_action(state, %{} = params, %DateTime{} = now) do
    action = value(params, :action)
    step = value(params, :step)

    cond do
      action not in @actions ->
        {:error, :invalid_onboarding_action}

      action in ~w(complete skip reopen) and step not in @steps ->
        {:error, :invalid_onboarding_action}

      true ->
        {:ok, do_apply(action, step, state, DateTime.to_iso8601(now))}
    end
  end

  def apply_action(_state, _params, _now), do: {:error, :invalid_onboarding_action}

  defp do_apply("complete", step, state, _now),
    do: state |> add("completed", step) |> remove("skipped", step)

  defp do_apply("skip", step, state, _now),
    do: state |> add("skipped", step) |> remove("completed", step)

  defp do_apply("reopen", step, state, _now),
    do: state |> remove("completed", step) |> remove("skipped", step)

  defp do_apply("dismiss", _step, state, now), do: Map.put(state, "dismissed_at", now)
  defp do_apply("restore", _step, state, _now), do: Map.put(state, "dismissed_at", nil)

  defp do_apply("tour_completed", _step, state, now),
    do: state |> Map.put("tour_completed_at", now) |> add("completed", "tour")

  defp step_signal("tour", state, _signals), do: not is_nil(state["tour_completed_at"])
  defp step_signal(step, _state, signals), do: Map.get(signals, step) == true

  defp add(state, key, step), do: Map.update!(state, key, &Enum.uniq(&1 ++ [step]))
  defp remove(state, key, step), do: Map.update!(state, key, &List.delete(&1, step))

  defp known_steps(list) when is_list(list),
    do: list |> Enum.filter(&(&1 in @steps)) |> Enum.uniq()

  defp known_steps(_list), do: []

  defp string_or_nil(value) when is_binary(value), do: value
  defp string_or_nil(_value), do: nil

  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
