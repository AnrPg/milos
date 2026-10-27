defmodule Palee.Identity.Ports.AccountDeletionStore do
  @moduledoc "ADR-211: storage of self-service account deletions."
  alias Palee.Identity.AccountDeletion

  @type id :: Ecto.UUID.t()

  @doc "The login's open request, if any."
  @callback for_login(id()) :: AccountDeletion.t() | nil
  @callback get(id()) :: AccountDeletion.t() | nil

  @doc """
  Opens a request (`attrs`: login_id, user_id, scope, status, confirmed_at,
  scheduled_for). A request still awaiting confirmation is replaced; a
  scheduled one is kept and `{:error, :already_scheduled}` returned.
  """
  @callback open(map()) :: {:ok, AccountDeletion.t()} | {:error, :already_scheduled}

  @doc "Moves an awaiting request to `scheduled` (row locked)."
  @callback schedule(id(), DateTime.t(), DateTime.t()) ::
              {:ok, AccountDeletion.t()} | {:error, :not_found | :already_scheduled}

  @doc "Drops the request (cancelled, or carried out)."
  @callback delete(id()) :: :ok

  @doc "Scheduled requests whose grace ended at `now`, oldest first."
  @callback due(DateTime.t(), pos_integer()) :: [AccountDeletion.t()]

  @doc "Active businesses where one of these profiles is the only active owner."
  @callback sole_owned_organizations([id()]) :: [%{id: id(), name: String.t()}]

  @doc "Whether the profile appears in accounting records a business must keep."
  @callback has_retained_records?(id()) :: boolean()

  @doc """
  Keeps the profile row for the records that need it, with nothing left
  that names the person: a placeholder handle and name, no avatar, moved to
  a login of its own that nobody can sign in to.
  """
  @callback anonymize_profile(id()) :: :ok | {:error, :not_found}

  @doc "Deletes the login once no profile is left on it (its last one was anonymised)."
  @callback delete_login_if_empty(id()) :: :ok
end
