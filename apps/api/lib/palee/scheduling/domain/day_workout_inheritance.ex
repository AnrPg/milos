defmodule Palee.Scheduling.Domain.DayWorkoutInheritance do
  @moduledoc """
  Which WOD a class takes from the day's WODs (ADR-230).

  A day may hold several rules, each for «all» or one class type, and for
  «all» or one branch. A class follows the most specific rule that covers it:
  a class-type rule beats an all-types rule, and a branch rule beats an
  all-branches rule of the same kind. An all-types rule covers only classes
  (`kind: "class"`), never events; an event takes a day WOD only from a rule
  naming its type.

  A class's own WOD (set on the class, its series, or a per-class edit) beats
  every rule: it is an override, recorded as `day_workout_id: nil`. A class
  that inherited records the rule (`day_workout_id`), so it follows later
  changes of that day and can be told apart from an override.

  Classes that have started are history and never change. A standalone class
  people booked keeps a WOD (ADR-176): when its rule stops covering it, the WOD
  stays as its own instead of being removed.

  Pure: no Repo, no clock (`now` is passed in).
  """

  @type rule :: %{
          required(:id) => String.t(),
          required(:class_type_id) => String.t() | nil,
          required(:location_id) => String.t() | nil,
          required(:master_workout_id) => String.t(),
          optional(atom()) => term()
        }

  @type class :: %{
          required(:scheduled_at) => DateTime.t(),
          required(:class_type_id) => String.t() | nil,
          required(:master_workout_id) => String.t() | nil,
          required(:day_workout_id) => String.t() | nil,
          optional(:location_id) => String.t() | nil,
          optional(:class_kind) => String.t() | nil,
          optional(:class_series_id) => String.t() | nil,
          optional(:booked) => boolean(),
          optional(atom()) => term()
        }

  @type change ::
          :keep
          | {:inherit, rule()}
          | :clear
          | :detach

  @doc "The class's WOD came from a day rule."
  def inherited?(class), do: not is_nil(Map.get(class, :day_workout_id))

  @doc "The class has a WOD of its own (set on it, not inherited)."
  def own?(class),
    do: not is_nil(Map.get(class, :master_workout_id)) and not inherited?(class)

  @doc "`\"day\"`, `\"class\"` or nil: where the class's WOD comes from."
  def source(class) do
    cond do
      inherited?(class) -> "day"
      own?(class) -> "class"
      true -> nil
    end
  end

  @doc "Whether `rule` covers `class`."
  def covers?(rule, class) do
    type_matches?(rule, class) and location_matches?(rule, class)
  end

  defp type_matches?(%{class_type_id: nil}, class),
    do: Map.get(class, :class_kind, "class") in ["class", nil]

  defp type_matches?(%{class_type_id: type_id}, class), do: type_id == class.class_type_id

  defp location_matches?(%{location_id: nil}, _class), do: true

  defp location_matches?(%{location_id: location_id}, class),
    do: location_id == Map.get(class, :location_id)

  @doc "How specific a rule is: a class type outranks a branch."
  def specificity(rule) do
    if(is_nil(rule.class_type_id), do: 0, else: 2) + if(is_nil(rule.location_id), do: 0, else: 1)
  end

  @doc "The rule a class follows among the day's `rules`, or nil."
  def winner(rules, class) do
    rules
    |> Enum.filter(&covers?(&1, class))
    |> Enum.max_by(&specificity/1, fn -> nil end)
  end

  @doc """
  What to do with `class` given its day's `rules`:

    * `:keep` leaves it alone;
    * `{:inherit, rule}` sets the rule's WOD and records the rule;
    * `:clear` removes an inherited WOD no rule covers any more;
    * `:detach` keeps that WOD as the class's own (a booked standalone class).

  `replace_own: true` also hands a covering rule's WOD to classes with their
  own WOD (the «replace these too» choice when a day WOD is set), and
  `only_rule_id` limits that to the rule being set.
  """
  @spec change(class(), [rule()], DateTime.t(), keyword()) :: change()
  def change(class, rules, %DateTime{} = now, opts \\ []) do
    rule = winner(rules, class)

    cond do
      started?(class, now) -> :keep
      own?(class) -> replace_own(class, rule, opts)
      rule -> inherit(class, rule)
      inherited?(class) -> orphaned(class)
      true -> :keep
    end
  end

  defp replace_own(_class, nil, _opts), do: :keep

  defp replace_own(_class, rule, opts) do
    replace? = Keyword.get(opts, :replace_own, false)
    only = Keyword.get(opts, :only_rule_ids)

    if replace? and (is_nil(only) or rule.id in only), do: {:inherit, rule}, else: :keep
  end

  defp inherit(class, rule) do
    if class.day_workout_id == rule.id and class.master_workout_id == rule.master_workout_id,
      do: :keep,
      else: {:inherit, rule}
  end

  defp orphaned(class) do
    if Map.get(class, :booked, false) and is_nil(Map.get(class, :class_series_id)),
      do: :detach,
      else: :clear
  end

  @doc "The class has started: its WOD is history."
  def started?(class, now), do: DateTime.compare(class.scheduled_at, now) != :gt

  @doc """
  The classes of a day split by what setting the rules `rule_ids` among
  `rules` would do: `inherit` (will take a day WOD), `own` (keep their own
  WOD), `started`. Classes whose winning rule is another one are left out.
  """
  def preview(classes, rules, %DateTime{} = now, rule_ids) do
    Enum.reduce(classes, %{inherit: [], own: [], started: []}, fn class, acc ->
      case winner(rules, class) do
        %{id: id} ->
          if id in rule_ids, do: Map.update!(acc, bucket(class, now), &[class | &1]), else: acc

        nil ->
          acc
      end
    end)
    |> Map.new(fn {key, list} -> {key, Enum.sort_by(list, & &1.scheduled_at, DateTime)} end)
  end

  @doc """
  The day's rules once `candidates` are saved: a candidate replaces the rule
  of the same scope.
  """
  def with_candidates(rules, candidates) do
    scopes = MapSet.new(candidates, &scope/1)
    Enum.reject(rules, &MapSet.member?(scopes, scope(&1))) ++ candidates
  end

  defp scope(rule), do: {rule.class_type_id, rule.location_id}

  defp bucket(class, now) do
    cond do
      started?(class, now) -> :started
      own?(class) -> :own
      true -> :inherit
    end
  end
end
