defmodule Palee.Scaling.ScalingAdvisor do
  @moduledoc "Facade over the configured scaling advisor adapter (ADR-174)."

  @behaviour Palee.Scaling.Ports.ScalingAdvisor

  defp adapter, do: Application.fetch_env!(:palee, :scaling_advisor)

  @impl true
  def suggest(input, options), do: adapter().suggest(input, options)

  @doc "The platform default model, used when the gym set none."
  def default_model do
    :palee
    |> Application.get_env(:anthropic, [])
    |> Keyword.get(:scaling_model, "claude-sonnet-5-5")
  end
end
