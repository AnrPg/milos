defmodule Palee.Identity.ReleasedEmailStore do
  @moduledoc "Facade over the released-address storage adapter (ADR-211)."
  @behaviour Palee.Identity.Ports.ReleasedEmailStore

  @impl true
  def reserve(email, login_id, until, now), do: impl().reserve(email, login_id, until, now)
  @impl true
  def reserved_for_other?(email, login_id, now),
    do: impl().reserved_for_other?(email, login_id, now)

  @impl true
  def release(email, login_id), do: impl().release(email, login_id)

  defp impl,
    do:
      Application.get_env(
        :palee,
        :released_email_store,
        Palee.Infrastructure.Identity.EctoReleasedEmailStore
      )
end
