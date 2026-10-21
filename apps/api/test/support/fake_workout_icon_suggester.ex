defmodule Palee.FakeWorkoutIconSuggester do
  @moduledoc """
  Test stand-in for Gemini. Answers by keyword so tests stay deterministic;
  "chatty" titles return prose to exercise the single-emoji validation.
  """

  @behaviour Palee.Application.Ports.WorkoutIconSuggester

  @impl true
  def suggest(%{title: title}, _metering) do
    cond do
      title =~ ~r/deload/i -> {:ok, "💆"}
      title =~ ~r/mobility/i -> {:ok, " 🧘 "}
      title =~ ~r/chatty/i -> {:ok, "Sure! I'd pick 🏋️ for this one."}
      true -> {:error, :not_configured}
    end
  end
end
