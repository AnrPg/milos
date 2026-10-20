defmodule MilosTraining.Media.Ports.MediaStore do
  @moduledoc """
  Persistence port of the Media context (ADR-148, ADR-157). `scope` is
  `:tenant` (rows of the context's organization) or `:account` (rows of the
  context's user); every function stays inside that owner.
  """

  @type context :: map()
  @type scope :: :tenant | :account
  @type media :: map()
  @typedoc "The consumer an upload is attached to (ADR-157)."
  @type attachment :: %{type: String.t(), id: binary(), organization_id: binary() | nil}

  @callback create(context(), scope(), map()) :: {:ok, media()} | {:error, term()}
  @callback get(context(), scope(), binary()) :: media() | nil
  @callback list(context(), scope(), [binary()]) :: [media()]
  @callback mark_ready(context(), scope(), binary(), map()) :: {:ok, media()} | {:error, term()}
  @doc "pending → processing, with the stored size and real type."
  @callback mark_processing(context(), scope(), binary(), map()) ::
              {:ok, media()} | {:error, term()}
  @doc "processing → ready, with dimensions, renditions, placeholder and duration."
  @callback mark_processed(context(), scope(), binary(), map()) ::
              {:ok, media()} | {:error, term()}
  @doc "pending | processing → rejected."
  @callback mark_rejected(context(), scope(), binary(), atom()) ::
              {:ok, media()} | {:error, term()}
  @callback set_attached(context(), scope(), [binary()], DateTime.t() | nil) :: :ok
  @doc "Attaches unattached, not rejected uploads to a consumer; answers how many it took."
  @callback attach(context(), scope(), [binary()], attachment(), DateTime.t()) ::
              {:ok, non_neg_integer()}
  @callback update_alt_text(context(), scope(), binary(), String.t() | nil) ::
              {:ok, media()} | {:error, term()}
  @doc "Open uploads since `since` and bytes stored, for the quota guard."
  @callback usage(context(), scope(), DateTime.t()) :: %{
              open_uploads: non_neg_integer(),
              bytes: non_neg_integer()
            }
  @callback delete(context(), scope(), [binary()]) :: {:ok, [media()]}
  @callback list_unattached(context(), scope(), DateTime.t()) :: [media()]
  @doc "System path: people with unattached account media older than `before`."
  @callback account_orphan_owner_ids(DateTime.t()) :: [binary()]
  @doc "System path: `{user_id, media_id}` of uploads attached to a post that is gone."
  @callback dangling_post_media(DateTime.t(), pos_integer()) :: [{binary(), binary()}]
  @doc "System path: `{user_id, media_id}` of attached uploads stuck before `ready`."
  @callback stale_post_media(DateTime.t(), pos_integer()) :: [{binary(), binary()}]
end
