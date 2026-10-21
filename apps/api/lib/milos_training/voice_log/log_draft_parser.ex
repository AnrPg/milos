defmodule MilosTraining.VoiceLog.LogDraftParser do
  @moduledoc "Facade over the configured log-draft parser adapter (ADR-175)."

  @behaviour MilosTraining.VoiceLog.Ports.LogDraftParser

  defp adapter, do: Application.fetch_env!(:milos_training, :log_draft_parser)

  @impl true
  def parse(input, options), do: adapter().parse(input, options)

  @doc "The platform default model, used when the gym set none."
  def default_model do
    :milos_training
    |> Application.get_env(:anthropic, [])
    |> Keyword.get(:voice_model, "claude-sonnet-5-5")
  end
end
