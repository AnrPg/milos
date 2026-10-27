defmodule Palee.Identity.EmailChangeStore do
  @moduledoc "Facade over the email change storage adapter (ADR-207)."
  @behaviour Palee.Identity.Ports.EmailChangeStore

  @impl true
  def transaction(fun), do: impl().transaction(fun)
  @impl true
  def get_login(login_id), do: impl().get_login(login_id)
  @impl true
  def lock_login(login_id), do: impl().lock_login(login_id)
  @impl true
  def get_pending(login_id), do: impl().get_pending(login_id)
  @impl true
  def put_pending(login_id, new_email, requested_at, expires_at),
    do: impl().put_pending(login_id, new_email, requested_at, expires_at)

  @impl true
  def delete_pending(login_id), do: impl().delete_pending(login_id)
  @impl true
  def email_taken?(email, except_login_id), do: impl().email_taken?(email, except_login_id)
  @impl true
  def set_login_email(login_id, email, now, opts \\ []),
    do: impl().set_login_email(login_id, email, now, opts)

  defp impl,
    do:
      Application.get_env(
        :palee,
        :email_change_store,
        Palee.Infrastructure.Identity.EctoEmailChangeStore
      )
end
