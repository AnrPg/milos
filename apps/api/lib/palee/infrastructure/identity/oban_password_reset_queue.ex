defmodule Palee.Infrastructure.Identity.ObanPasswordResetQueue do
  @moduledoc """
  Oban adapter of the password reset queue (ADR-206): one
  `PasswordResetRequestJob` per request. The job row is inserted with
  `Repo.insert` like the email outbox's, so it also lands in the test
  sandbox where Oban is not started.
  """

  @behaviour Palee.Identity.Ports.PasswordResetQueue

  alias Palee.Repo
  alias Palee.Workers.PasswordResetRequestJob

  @impl true
  def submit(args) do
    case args |> PasswordResetRequestJob.new() |> Repo.insert() do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
