defmodule MilosTraining.Scaling.ScalingAdvisor do
  @moduledoc "Facade over the configured scaling advisor adapter (ADR-174)."

  @behaviour MilosTraining.Scaling.Ports.ScalingAdvisor

  defp adapter, do: Application.fetch_env!(:milos_training, :scaling_advisor)

  @impl true
  def suggest(input, options), do: adapter().suggest(input, options)

  @doc "The platform default model, used when the gym set none."
  def default_model do
    :milos_training
    |> Application.get_env(:anthropic, [])
    |> Keyword.get(:scaling_model, "claude-sonnet-5-5")
  end
end
