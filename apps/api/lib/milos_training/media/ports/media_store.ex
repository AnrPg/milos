defmodule MilosTraining.Media.Ports.MediaStore do
  @moduledoc """
  Persistence port of the Media context (ADR-148). `scope` is `:tenant`
  (rows of the context's organization) or `:account` (rows of the context's
  user); every function stays inside that owner.
  """

  @type context :: map()
  @type scope :: :tenant | :account
  @type media :: map()

  @callback create(context(), scope(), map()) :: {:ok, media()} | {:error, term()}
  @callback get(context(), scope(), binary()) :: media() | nil
  @callback list(context(), scope(), [binary()]) :: [media()]
  @callback mark_ready(context(), scope(), binary(), map()) :: {:ok, media()} | {:error, term()}
  @callback set_attached(context(), scope(), [binary()], DateTime.t() | nil) :: :ok
  @callback delete(context(), scope(), [binary()]) :: {:ok, [media()]}
  @callback list_unattached(context(), scope(), DateTime.t()) :: [media()]
  @doc "System path: people with unattached account media older than `before`."
  @callback account_orphan_owner_ids(DateTime.t()) :: [binary()]
end
