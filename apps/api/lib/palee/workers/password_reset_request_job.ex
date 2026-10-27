defmodule Palee.Workers.PasswordResetRequestJob do
  @moduledoc """
  ADR-206: works out one "forgot password" request in the background
  (`PasswordRecovery.request/2`): the reset email to a verified address, or
  the handler request of ADR-187. The HTTP answer never waits for it.

  The args hold what the person typed (an email or @handle) until Oban
  prunes the job; never a token or a password.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Palee.Application.PasswordRecovery

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"identifier" => identifier} = args}) do
    :ok =
      PasswordRecovery.request(identifier,
        cant_access_email: args["cant_access_email"] == true,
        locale: args["locale"],
        requester_key: decode(args["requester_key"])
      )
  end

  def perform(_job), do: {:cancel, :invalid_args}

  defp decode(key) when is_binary(key) do
    case Base.url_decode64(key, padding: false) do
      {:ok, raw} -> raw
      :error -> nil
    end
  end

  defp decode(_key), do: nil
end
