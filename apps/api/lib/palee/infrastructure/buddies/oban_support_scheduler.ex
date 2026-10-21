defmodule Palee.Infrastructure.Buddies.ObanSupportScheduler do
  @moduledoc "Oban adapter of the support scheduler: one unique job per request and step."

  @behaviour Palee.Buddies.Ports.SupportScheduler

  require Logger

  alias Palee.Workers.SupportRequestJob

  @impl true
  def schedule(user_id, request_id, steps) do
    if Application.get_env(:palee, :start_oban, true) do
      Enum.each(steps, fn {step, at} ->
        %{user_id: user_id, request_id: request_id, step: Atom.to_string(step)}
        |> SupportRequestJob.new(scheduled_at: at)
        |> Oban.insert()
        |> case do
          {:ok, _job} -> :ok
          {:error, reason} -> Logger.warning("support_step_schedule_failed #{inspect(reason)}")
        end
      end)
    end

    :ok
  end
end
