defmodule Palee.Email.Ports.MessageStore do
  @moduledoc """
  Persistence port of the outbox, its suppression list and the counts the
  budgets read (ADR-203). The tables are platform tables with no RLS, so no
  session scope is needed; calls made inside a caller's transaction join it.
  """

  alias Palee.Email.{Message, Suppression}

  @type id :: binary()

  @doc """
  Inserts the message and its delivery job (`job` is an `Oban.Job`
  changeset builder: `fn message -> changeset end`) in one transaction.
  A message whose `idempotency_key` already exists is not inserted again:
  `{:ok, existing}` comes back.
  """
  @callback insert_with_job(map(), (Message.t() -> Ecto.Changeset.t())) ::
              {:ok, Message.t()} | {:error, Ecto.Changeset.t() | term()}

  @callback get(id()) :: Message.t() | nil
  @callback get_by_idempotency_key(String.t()) :: Message.t() | nil

  @doc "Messages whose idempotency key starts with `prefix`, newest first."
  @callback list_by_idempotency_prefix(String.t()) :: [Message.t()]

  @doc "Messages matching every given field (`kind`, `to_address`, `status`, ...), newest first."
  @callback list(keyword()) :: [Message.t()]

  @doc "Sets the given fields on a message (`status`, `attempts`, `last_error`, ...)."
  @callback update(Message.t(), map()) :: {:ok, Message.t()} | {:error, term()}

  @doc "How many messages were sent since `since`."
  @callback count_sent_since(DateTime.t()) :: non_neg_integer()

  @doc """
  The messages of `kind` to `address` inserted since `since` that were not
  refused (`failed` and `suppressed` ones are left out): their count and
  the newest one's insertion time.
  """
  @callback recent_to(String.t(), String.t(), DateTime.t()) ::
              %{count: non_neg_integer(), last_at: DateTime.t() | nil}

  @callback suppressed?(binary()) :: boolean()
  @callback suppress(binary(), String.t()) :: {:ok, Suppression.t()} | {:error, term()}
  @callback unsuppress(binary()) :: :ok
end
