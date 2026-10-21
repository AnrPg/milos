defmodule Palee.Scaling.Domain.SuggestionPolicy do
  @moduledoc """
  The life of a scaling suggestion (ADR-174), pure.

      pending ──approve──▶ approved      (the only state a member ever reads)
         │  └──dismiss──▶ dismissed
         └─(inputs changed)─▶ superseded
      no_change ─(inputs changed)─▶ superseded

  * Coach approval is mandatory: nothing but `approve/4` produces
    `approved`, and only `member_view/1` of an approved row leaves the staff
    side.
  * The coach may untick changes and rewrite the suggested text before
    approving; at least one change or the scale level must remain.
  * An approved or dismissed suggestion is the coach's decision and is never
    regenerated; a pending (or «no change») one is replaced when the workout
    or the athlete's injuries changed.
  * Approved changes become ADR-050 modification patches on the exact
    section/exercise row (`patches/2`).
  """

  @window_days 2
  @max_note 500

  def window_days, do: @window_days

  @doc "The assignment dates the scan looks at: today and the next #{@window_days} days."
  def scan_window(%Date{} = today), do: {today, Date.add(today, @window_days)}

  @doc """
  What to do with an athlete's assignment given the latest live suggestion
  and the current input digest: `:generate`, `{:replace, latest}` or `:skip`.
  """
  def next_step(nil, _digest), do: :generate
  def next_step(%{status: status}, _digest) when status in ["approved", "dismissed"], do: :skip
  def next_step(%{input_digest: digest}, digest), do: :skip

  def next_step(%{status: status} = latest, _digest) when status in ["pending", "no_change"],
    do: {:replace, latest}

  def next_step(_latest, _digest), do: :generate

  @doc """
  Changes that approve a pending suggestion. `params`: `items` (optional,
  `[%{id, include, suggested}]`; omitted means all as proposed),
  `scale_level_slug` (optional; `nil` drops it), `coach_note` (optional).
  """
  def approve(%{status: "pending"} = suggestion, params, actor_id, now) do
    with {:ok, items} <- reviewed_items(suggestion.items, Map.get(params, :items)),
         {:ok, note} <- note(Map.get(params, :coach_note)) do
      scale = Map.get(params, :scale_level_slug, suggestion.scale_level_slug)
      scale = if scale == suggestion.scale_level_slug, do: scale, else: nil

      if items == [] and is_nil(scale) do
        {:error, :nothing_to_approve}
      else
        {:ok,
         %{
           status: "approved",
           items: items,
           scale_level_slug: scale,
           coach_note: note,
           modifications: patches(suggestion.id, items),
           reviewed_by_id: actor_id,
           reviewed_at: now
         }}
      end
    end
  end

  def approve(_suggestion, _params, _actor_id, _now), do: {:error, :already_reviewed}

  @doc "Changes that dismiss a pending suggestion."
  def dismiss(%{status: "pending"}, actor_id, now),
    do: {:ok, %{status: "dismissed", reviewed_by_id: actor_id, reviewed_at: now}}

  def dismiss(_suggestion, _actor_id, _now), do: {:error, :already_reviewed}

  defp reviewed_items(items, nil), do: {:ok, items}

  defp reviewed_items(items, reviews) when is_list(reviews) do
    by_id = Map.new(reviews, &{to_string(field(&1, :id)), &1})

    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, kept} ->
      review = Map.get(by_id, field(item, :id))

      case review_item(item, review) do
        :drop -> {:cont, {:ok, kept}}
        {:ok, item} -> {:cont, {:ok, [item | kept]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, kept} -> {:ok, Enum.reverse(kept)}
      error -> error
    end
  end

  defp reviewed_items(_items, _reviews), do: {:error, :bad_request}

  # A change the coach did not mention is kept as proposed.
  defp review_item(item, nil), do: {:ok, item}

  defp review_item(item, review) do
    cond do
      field(review, :include) == false ->
        :drop

      field(item, :change) == "skip" ->
        {:ok, item}

      is_binary(field(review, :suggested)) ->
        case String.trim(field(review, :suggested)) do
          "" -> {:error, :invalid_suggested}
          text -> {:ok, put(item, :suggested, String.slice(text, 0, 120))}
        end

      true ->
        {:ok, item}
    end
  end

  defp note(nil), do: {:ok, nil}

  defp note(text) when is_binary(text) do
    case String.trim(text) do
      "" ->
        {:ok, nil}

      trimmed when byte_size(trimmed) <= @max_note * 4 ->
        {:ok, String.slice(trimmed, 0, @max_note)}

      _too_long ->
        {:error, :invalid_coach_note}
    end
  end

  defp note(_text), do: {:error, :invalid_coach_note}

  @doc """
  ADR-050 modification patches for approved changes: one per change, on the
  change's section and exercise, with the advisor's (or coach's) reason as
  the note. Patch ids are stable per suggestion and change.
  """
  def patches(suggestion_id, items) do
    Enum.map(items, fn item ->
      {type, patch_field, canonical, actual} = patch_values(item)

      %{
        "patch_id" => "scaling-#{suggestion_id}-#{field(item, :id)}",
        "type" => type,
        "field" => patch_field,
        "section_id" => field(item, :section_id),
        "section_name" => field(item, :section_name),
        "exercise_id" => field(item, :exercise_id),
        "exercise_name" => field(item, :exercise_name),
        "canonical_value" => canonical,
        "actual_value" => actual,
        "note" => field(item, :reason)
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
    end)
  end

  defp patch_values(item) do
    prescribed = field(item, :prescribed)
    suggested = field(item, :suggested)

    case field(item, :change) do
      "substitute" ->
        {"exercise_substituted", "exercise_name", field(item, :exercise_name), suggested}

      "load" ->
        {"weight_changed", "load", prescribed, suggested}

      "reps" ->
        {"reps_changed", "reps", prescribed, suggested}

      "skip" ->
        {"skipped", "skipped", false, true}

      _other ->
        {"other", "prescription_value", prescribed, suggested}
    end
  end

  @doc "What the member reads: only an approved suggestion, never the rest."
  def member_view(%{status: "approved"} = suggestion) do
    %{
      id: suggestion.id,
      scheduled_for: suggestion.scheduled_for,
      scale_level_slug: suggestion.scale_level_slug,
      coach_note: suggestion.coach_note,
      reviewed_at: suggestion.reviewed_at,
      items:
        Enum.map(suggestion.items, fn item ->
          %{
            exercise_id: field(item, :exercise_id),
            section_id: field(item, :section_id),
            exercise_name: field(item, :exercise_name),
            change: field(item, :change),
            suggested: field(item, :suggested),
            reason: field(item, :reason)
          }
        end),
      modifications: suggestion.modifications
    }
  end

  def member_view(_suggestion), do: nil

  defp put(item, key, value) do
    if Map.has_key?(item, to_string(key)) and not Map.has_key?(item, key),
      do: Map.put(item, to_string(key), value),
      else: Map.put(item, key, value)
  end

  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, to_string(key)))
  defp field(_map, _key), do: nil
end
