defmodule MilosTraining.Workers.SupportRequestJob do
  @moduledoc """
  The timed steps of one «Χρειάζομαι στήριξη» (ADR-160 §2): `deliver` tells
  the buddies once the undo window passed; `nudge` gives the sender the
  calm no-reply card after ten minutes. Both are idempotent.
  """

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5,
    unique: [period: :infinity, keys: [:request_id, :step]]

  alias MilosTraining.Application.SupportRequests

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "request_id" => id, "step" => "deliver"}}),
    do: ok(SupportRequests.deliver(user_id, id))

  def perform(%Oban.Job{args: %{"user_id" => user_id, "request_id" => id, "step" => "nudge"}}),
    do: ok(SupportRequests.nudge(user_id, id))

  def perform(_job), do: {:cancel, :unknown_step}

  # Both steps answer :ok or {:error, :not_found}; a vanished request is done.
  defp ok(_result), do: :ok
end
