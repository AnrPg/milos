defmodule MilosTraining.Workouts.Queries.AnalyzeFreeText do
  @moduledoc """
  Reads a free-text workout through the configured `WorkoutTextAnalyzer` and
  validates the result against the canonical workout schema. Read-only: the
  analysis is a proposal; nothing is persisted until the coach publishes.
  """

  alias MilosTraining.Workouts.Domain.FreeTextAnalysis

  @max_length 20_000

  def call(text, options \\ %{})

  def call(text, options) when is_binary(text) do
    trimmed = String.trim(text)

    cond do
      trimmed == "" ->
        {:error, :text_required}

      String.length(trimmed) > @max_length ->
        {:error, :text_too_long}

      true ->
        with {:ok, raw} <- analyzer().analyze(trimmed, options) do
          {:ok, FreeTextAnalysis.normalize(raw, trimmed)}
        end
    end
  end

  def call(_text, _options), do: {:error, :text_required}

  def max_length, do: @max_length

  defp analyzer, do: Application.fetch_env!(:milos_training, :workout_text_analyzer)
end
