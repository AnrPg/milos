defmodule Palee.Application.AnalyzeFreeTextWorkout do
  @moduledoc """
  Admin use case: ask the workout assistant to read a free-text workout and
  return canonical fields, actionable issues and missing-field suggestions in
  the coach's language. The model calls it makes are recorded as the gym's AI
  usage (ADR-152).
  """

  alias Palee.{Organizations, Workouts}

  @doc "Analyzes the text, or `{:error, :assistant_disabled}` when the gym switched the assistant off (ADR-179)."
  def call(context, params) when is_map(params) do
    if Organizations.wod_assistant_enabled?(context),
      do: analyze(context, params),
      else: {:error, :assistant_disabled}
  end

  defp analyze(context, params) do
    text = Map.get(params, :text) || Map.get(params, "text")
    locale = Map.get(params, :locale) || Map.get(params, "locale")

    Workouts.analyze_free_text(text, %{
      locale: supported_locale(locale),
      # ADR-152: the model calls are metered for the coach's gym.
      metering: %{
        organization_id: Map.get(context, :organization_id),
        user_id: Map.get(context, :user_id)
      }
    })
  end

  # The analyzer maps the locale to a language name and falls back to English
  # for anything it does not know; only bound the size here.
  defp supported_locale(locale) when is_binary(locale) and byte_size(locale) in 2..10, do: locale
  defp supported_locale(_locale), do: "en"
end
