defmodule MilosTraining.Partners.Domain.ProfilePolicy do
  @moduledoc """
  A Partners profile (ADR-169 §1, plan D6). Pure.

  What a member says about training: a level, the times they train, up to
  three goals and an optional line of at most 140 characters. Gender and a
  gender preference are optional, used only to honour preferences and
  never shown to anyone. Lists keep a canonical order so two profiles
  compare cleanly.
  """

  @levels ~w(beginner intermediate advanced)
  @times ~w(early midday afternoon evening weekend)
  @goals ~w(strength conditioning weight_loss skills competition consistency)
  @genders ~w(woman man other)
  @gender_preferences ~w(any women men)
  @max_goals 3
  @about_max 140

  def levels, do: @levels
  def times, do: @times
  def goals, do: @goals
  def genders, do: @genders
  def gender_preferences, do: @gender_preferences
  def max_goals, do: @max_goals
  def about_max, do: @about_max

  @doc """
  The profile attributes from a request: every field is checked and
  normalized (trimmed `about`, deduplicated lists in canonical order). With
  `current`, missing fields keep their current values.
  """
  def normalize(params, current \\ nil) when is_map(params) do
    current = current || %{}

    with {:ok, level} <- level(fetch(params, :level, Map.get(current, :level))),
         {:ok, times} <- list(fetch(params, :times, Map.get(current, :times)), @times, :times),
         {:ok, goals} <- list(fetch(params, :goals, Map.get(current, :goals)), @goals, :goals),
         :ok <- goal_count(goals),
         {:ok, about} <- about(fetch(params, :about, Map.get(current, :about))),
         {:ok, gender} <- gender(fetch(params, :gender, Map.get(current, :gender))),
         {:ok, preference} <-
           preference(
             fetch(params, :gender_preference, Map.get(current, :gender_preference, "any"))
           ),
         {:ok, active} <- active(fetch(params, :active, Map.get(current, :active, true))) do
      {:ok,
       %{
         level: level,
         times: times,
         goals: goals,
         about: about,
         gender: gender,
         gender_preference: preference,
         active: active
       }}
    end
  end

  @doc "A suspended profile stays off whatever its owner asks."
  def check_activation(%{suspended_at: %DateTime{}}, true),
    do: {:error, :partner_profile_suspended}

  def check_activation(_profile, _active), do: :ok

  @doc "Whether the profile takes part in its club's deck."
  def live?(%{active: true, suspended_at: nil}), do: true
  def live?(_profile), do: false

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
end
