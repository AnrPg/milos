defmodule MilosTraining.FakeLogDraftParser do
  @moduledoc """
  Test stand-in behind the `LogDraftParser` port (ADR-175). Deterministic:
  answers a fixed draft for any transcript. Tells the calling process what
  it was asked (`{:log_draft_parser_called, input, options}`). Keys
  starting with `rejected` answer as a rejected key, `invalid` as an
  unusable answer.
  """

  @behaviour MilosTraining.VoiceLog.Ports.LogDraftParser

  @impl true
  def parse(input, options) do
    send(self(), {:log_draft_parser_called, input, options})

    case Map.get(options, :api_key) do
      nil -> {:error, :parser_not_configured}
      "rejected" <> _rest -> {:error, :parser_key_rejected}
      "invalid" <> _rest -> {:ok, %{"exercises" => "not a list"}}
      _key -> {:ok, answer()}
    end
  end

  defp answer do
    %{
      "title" => "Squats και κωπηλατική",
      "duration_minutes" => 45,
      "perceived_effort" => 7,
      "days_ago" => 0,
      "notes" => nil,
      "exercises" => [
        %{"name" => "Back Squat", "sets" => 5, "reps" => 5, "load" => 100, "load_unit" => "kg"},
        %{"name" => "Row", "sets" => nil, "reps" => nil, "load" => nil, "load_unit" => nil},
        %{"name" => "  ", "sets" => 3, "reps" => 3, "load" => nil, "load_unit" => nil}
      ]
    }
  end
end
