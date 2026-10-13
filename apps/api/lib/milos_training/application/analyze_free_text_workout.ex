defmodule MilosTraining.Application.AnalyzeFreeTextWorkout do
  @moduledoc """
  Admin use case: ask the workout assistant to read a free-text workout and
  return canonical fields, actionable issues and missing-field suggestions in
  the coach's language.
  """

  alias MilosTraining.Workouts

  def call(_context, params) when is_map(params) do
    text = Map.get(params, :text) || Map.get(params, "text")
    locale = Map.get(params, :locale) || Map.get(params, "locale")

    Workouts.analyze_free_text(text, %{locale: supported_locale(locale)})
  end

  # The analyzer maps the locale to a language name and falls back to English
  # for anything it does not know; only bound the size here.
  defp supported_locale(locale) when is_binary(locale) and byte_size(locale) in 2..10, do: locale
  defp supported_locale(_locale), do: "en"
end
