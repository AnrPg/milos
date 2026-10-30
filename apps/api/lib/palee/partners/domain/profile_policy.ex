defmodule Palee.Partners.Domain.ProfilePolicy do
  @moduledoc """
  A Partners profile (ADR-169 §1, plan D6; one per account since ADR-280).
  Pure.

  What a person says about training: a level, the times they train, up to
  three goals, up to five disciplines (keys of the box vocabulary, ADR-197)
  and an optional line of at most 140 characters. Gender and a
  gender preference are optional, used only to honour preferences and
  never shown to anyone. Lists keep a canonical order so two profiles
  compare cleanly. `show_box` (default on) lets the card name the box of an
  active membership. The first save needs the 18+ confirmation (ADR-280).
  """

  @levels ~w(beginner intermediate advanced)
  @times ~w(early midday afternoon evening weekend)
  @goals ~w(strength conditioning weight_loss skills competition consistency)
  @genders ~w(woman man other)
  @gender_preferences ~w(any women men)
  @max_goals 3
  @max_disciplines 5
  @about_max 140

  def levels, do: @levels
  def times, do: @times
  def goals, do: @goals
  def genders, do: @genders
  def gender_preferences, do: @gender_preferences
  def max_goals, do: @max_goals
  def max_disciplines, do: @max_disciplines
  def about_max, do: @about_max

  @doc """
  The profile attributes from a request: every field is checked and
  normalized (trimmed `about`, deduplicated lists in canonical order). With
  `current`, missing fields keep their current values. `disciplines` is the
  box vocabulary the disciplines are checked against.
  """
  def normalize(params, current \\ nil, disciplines \\ []) when is_map(params) do
    current = current || %{}

    with {:ok, level} <- level(fetch(params, :level, Map.get(current, :level))),
         {:ok, times} <- list(fetch(params, :times, Map.get(current, :times)), @times, :times),
         {:ok, goals} <- list(fetch(params, :goals, Map.get(current, :goals)), @goals, :goals),
         :ok <- goal_count(goals),
         {:ok, picked} <-
           disciplines(
             fetch(params, :disciplines, Map.get(current, :disciplines, [])),
             disciplines
           ),
         {:ok, about} <- about(fetch(params, :about, Map.get(current, :about))),
         {:ok, gender} <- gender(fetch(params, :gender, Map.get(current, :gender))),
         {:ok, preference} <-
           preference(
             fetch(params, :gender_preference, Map.get(current, :gender_preference, "any"))
           ),
         {:ok, active} <- active(fetch(params, :active, Map.get(current, :active, true))),
         {:ok, show_box} <-
           show_box(fetch(params, :show_box, Map.get(current, :show_box, true))) do
      {:ok,
       %{
         level: level,
         times: times,
         goals: goals,
         disciplines: picked,
         about: about,
         gender: gender,
         gender_preference: preference,
         active: active,
         show_box: show_box
       }}
    end
  end

  @doc """
  The 18+ confirmation (ADR-280): the first save needs `adult_confirmed:
  true` and records when; a saved profile keeps its confirmation.
  """
  def adult_confirmation(%{adult_confirmed_at: %DateTime{} = at}, _params, _now), do: {:ok, at}

  def adult_confirmation(_current, params, now) do
    if fetch(params, :adult_confirmed, false) == true,
      do: {:ok, now},
      else: {:error, :partner_adult_required}
  end

  @doc "Whether the profile takes part in the deck: on, and not paused in Ρυθμίσεις."
  def live?(%{active: true, paused_at: nil}), do: true
  def live?(_profile), do: false

  @doc "The Ρυθμίσεις switch: `paused_at` for `visible`."
  def pause_changes(%{paused_at: paused_at}, false, now), do: %{paused_at: paused_at || now}
  def pause_changes(_profile, true, _now), do: %{paused_at: nil}

  defp fetch(params, key, default) do
    case Map.fetch(params, key) do
      {:ok, value} -> value
      :error -> Map.get(params, Atom.to_string(key), default)
    end
  end

  defp level(level) when level in @levels, do: {:ok, level}
  defp level(_level), do: {:error, :invalid_partner_level}

  defp list(values, allowed, field) when is_list(values) do
    if values != [] and Enum.all?(values, &(&1 in allowed)),
      do: {:ok, Enum.filter(allowed, &(&1 in values))},
      else: {:error, :"invalid_partner_#{field}"}
  end

  defp list(_values, _allowed, field), do: {:error, :"invalid_partner_#{field}"}

  defp disciplines(nil, _allowed), do: {:ok, []}

  defp disciplines(values, allowed) when is_list(values) do
    if length(Enum.uniq(values)) <= @max_disciplines and Enum.all?(values, &(&1 in allowed)),
      do: {:ok, Enum.filter(allowed, &(&1 in values))},
      else: {:error, :invalid_partner_disciplines}
  end

  defp disciplines(_values, _allowed), do: {:error, :invalid_partner_disciplines}

  defp goal_count(goals) when length(goals) <= @max_goals, do: :ok
  defp goal_count(_goals), do: {:error, :invalid_partner_goals}

  defp about(nil), do: {:ok, nil}

  defp about(text) when is_binary(text) do
    case String.trim(text) do
      "" ->
        {:ok, nil}

      trimmed ->
        if String.length(trimmed) <= @about_max,
          do: {:ok, trimmed},
          else: {:error, :partner_about_too_long}
    end
  end

  defp about(_text), do: {:error, :partner_about_too_long}

  defp gender(nil), do: {:ok, nil}
  defp gender(""), do: {:ok, nil}
  defp gender(gender) when gender in @genders, do: {:ok, gender}
  defp gender(_gender), do: {:error, :invalid_partner_gender}

  defp preference(nil), do: {:ok, "any"}
  defp preference(preference) when preference in @gender_preferences, do: {:ok, preference}
  defp preference(_preference), do: {:error, :invalid_partner_gender_preference}

  defp active(value) when is_boolean(value), do: {:ok, value}
  defp active(_value), do: {:error, :invalid_partner_active}

  defp show_box(value) when is_boolean(value), do: {:ok, value}
  defp show_box(_value), do: {:error, :invalid_partner_show_box}
end
