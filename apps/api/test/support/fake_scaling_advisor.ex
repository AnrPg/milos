defmodule Palee.FakeScalingAdvisor do
  @moduledoc """
  Test stand-in behind the `ScalingAdvisor` port (ADR-174). Deterministic:
  every flagged movement gets a substitution, plus the first scale level.
  Tells the calling process what it was asked (`{:scaling_advisor_called,
  input, options}`). Keys starting with `rejected` answer as a rejected key,
  `invalid` as an unusable answer, `quiet` as «nothing to change».
  """

  @behaviour Palee.Scaling.Ports.ScalingAdvisor

  @impl true
  def suggest(input, options) do
    send(self(), {:scaling_advisor_called, input, options})

    case Map.get(options, :api_key) do
      nil -> {:error, :advisor_not_configured}
      "rejected" <> _rest -> {:error, :advisor_key_rejected}
      "invalid" <> _rest -> {:ok, %{"unexpected" => true}}
      "quiet" <> _rest -> {:ok, %{"summary" => "", "scale_level" => nil, "items" => []}}
      _key -> {:ok, answer(input)}
    end
  end

  defp answer(input) do
    flagged = MapSet.new(input.flagged_movements, & &1.name)

    items =
      input.workout.sections
      |> Enum.flat_map(& &1.movements)
      |> Enum.filter(&MapSet.member?(flagged, &1.name))
      |> Enum.map(fn movement ->
        %{
          "exercise_id" => movement.id,
          "change" => "substitute",
          "suggested" => "Box step-up",
          "reason" => "Λιγότερο φορτίο στο τραυματισμένο σημείο."
        }
      end)

    %{
      "summary" => "Ήπια προσαρμογή.",
      "scale_level" => input.scale_levels |> List.first(%{}) |> Map.get(:slug),
      "items" =>
        items ++
          [%{"exercise_id" => "not-in-workout", "change" => "skip", "reason" => "ignored"}]
    }
  end
end
