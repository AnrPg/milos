defmodule Palee.Identity.Ports.EmailChangeStore do
  @moduledoc "ADR-207: storage of pending email changes and the login's email."

  alias Palee.Identity.PendingEmailChange

  @type login_state :: %{
          id: Ecto.UUID.t(),
          email: String.t(),
          email_change_locked_until: DateTime.t() | nil
        }

  @doc "Runs `fun` in one transaction; `{:error, reason}` from it rolls back."
  @callback transaction((-> {:ok, term()} | {:error, term()})) :: {:ok, term()} | {:error, term()}
  @callback get_login(Ecto.UUID.t()) :: login_state() | nil
  @doc "Like `get_login/1`, and holds the login's row until the transaction ends."
  @callback lock_login(Ecto.UUID.t()) :: login_state() | nil
  @callback get_pending(Ecto.UUID.t()) :: PendingEmailChange.t() | nil
  @doc "Creates or replaces the login's one pending change."
  @callback put_pending(Ecto.UUID.t(), String.t(), DateTime.t(), DateTime.t()) ::
              {:ok, PendingEmailChange.t()} | {:error, term()}
  @callback delete_pending(Ecto.UUID.t()) :: :ok
  @doc "Whether another login already signs in with `email` (case-insensitive)."
  @callback email_taken?(String.t(), Ecto.UUID.t()) :: boolean()
  @doc """
  Makes `email` the login's address, verified at `now`, revokes every
  session of every profile (`security_version`) and drops the pending
  change. Option `:locked_until` also locks new changes until then.
  """
  @callback set_login_email(Ecto.UUID.t(), String.t(), DateTime.t(), keyword()) ::
              :ok | {:error, :email_unavailable | :not_found}
end
