defmodule Palee.Email do
  @moduledoc """
  Transactional email (ADR-203): every email Palee sends goes through this
  outbox. `enqueue/4` renders the email and stores it with its delivery job
  in one transaction; `Palee.Workers.DeliverEmailJob` sends it (queue
  `email`), within the daily budget, never to a suppressed address, with
  retries and backoff.

  Kinds are registered in `Palee.Email.Templates`; each one's
  `Palee.Email.Template` names its category (`security`, `account`,
  `transactional`). Single-use links for emails are in
  `Palee.Email.LinkTokens`.

  Telemetry: `[:palee, :email, event]` with `%{count: 1}` and
  `%{message_id, kind, category}` (plus `reason` for `:failed`), for
  `:enqueued`, `:sent`, `:failed` (given up), `:suppressed` and `:deferred`.
  No event carries the address.
  """

  alias Palee.Email.Commands.{DeliverEmail, EnqueueEmail}
  alias Palee.Email.Domain.{Address, SendingPolicy}
  alias Palee.Email.Message

  @type kind :: atom()
  @type reason ::
          :unknown_kind
          | :invalid_address
          | :invalid_category
          | :not_live
          | :suppressed
          | :throttled
          | :over_budget
          | term()

  @doc """
  Queues `kind` to `to`, rendered from `assigns`.

  Options:

    * `:locale` - the language to render in (default `"en"`);
    * `:login_id`, `:user_id` - whom the email is about, for the record;
    * `:organization_id` - the business that sends it: a `transactional`
      email is refused with `{:error, :not_live}` while that business is in
      demo mode (ADR-184);
    * `:idempotency_key` - a repeat with the same key returns the first
      message and sends nothing more (use a prefix per feature, e.g.
      `"owner_invitation:<invitation id>"`, to list them with
      `list_by_idempotency_prefix/1`);
    * `:category` - overrides the template's category;
    * `:now` - the current time (tests).

  `{:ok, message}` (status `queued`, or `deferred` past today's budget), or
  `{:error, reason}`: `:unknown_kind`, `:invalid_address`, `:not_live`,
  `:suppressed`, `:throttled` (this kind went to this address too recently
  or too often today), `:over_budget` (security mail past the daily hard
  cap), `:invalid_category`, or a changeset.
  """
  @spec enqueue(kind(), String.t(), map(), keyword()) :: {:ok, Message.t()} | {:error, reason()}
  def enqueue(kind, to, assigns, opts \\ []), do: EnqueueEmail.call(kind, to, assigns, opts)

  @doc """
  The delivery status of a message, by its id: `{:ok, summary}` with `id`,
  `kind`, `category`, `status` (`"queued" | "deferred" | "sent" | "failed" |
  "suppressed"`), `attempts`, `last_error`, `scheduled_at`, `sent_at`,
  `inserted_at`, `idempotency_key`; or `{:error, :not_found}`.
  """
  @spec status(binary()) :: {:ok, map()} | {:error, :not_found}
  def status(message_id) do
    case message_store().get(message_id) do
      nil -> {:error, :not_found}
      message -> {:ok, summary(message)}
    end
  end

  @doc "The summaries (see `status/1`) of the messages whose idempotency key starts with `prefix`, newest first."
  @spec list_by_idempotency_prefix(String.t()) :: [map()]
  def list_by_idempotency_prefix(prefix) when is_binary(prefix) and prefix != "",
    do: prefix |> message_store().list_by_idempotency_prefix() |> Enum.map(&summary/1)

  @doc "Whether `address` is on the suppression list."
  @spec suppressed?(String.t()) :: boolean()
  def suppressed?(address) do
    case Address.digest(address) do
      nil -> false
      digest -> message_store().suppressed?(digest)
    end
  end

  @doc """
  Puts `address` on the suppression list (`:bounce`, `:complaint` or
  `:manual`); nothing is mailed to it any more. Suppressing again updates
  the reason.
  """
  @spec suppress(String.t(), :bounce | :complaint | :manual) ::
          {:ok, Palee.Email.Suppression.t()} | {:error, term()}
  def suppress(address, reason) when reason in [:bounce, :complaint, :manual] do
    case Address.digest(address) do
      nil -> {:error, :invalid_address}
      digest -> message_store().suppress(digest, Atom.to_string(reason))
    end
  end

  @doc "Takes `address` off the suppression list."
  @spec unsuppress(String.t()) :: :ok
  def unsuppress(address) do
    case Address.digest(address) do
      nil -> :ok
      digest -> message_store().unsuppress(digest)
    end
  end

  @doc false
  # One delivery attempt, for DeliverEmailJob.
  def deliver(message_id, attempt, now \\ DateTime.utc_now()),
    do: DeliverEmail.call(message_id, attempt, now)

  @doc """
  The daily budget: `EMAIL_DAILY_BUDGET` (non-security mail, default 280)
  and `EMAIL_DAILY_HARD_CAP` (security mail, default 295).
  """
  def budget do
    configured = Map.new(Application.get_env(:palee, :email_budget, []))
    Map.merge(SendingPolicy.default_budget(), Map.take(configured, [:daily_budget, :hard_cap]))
  end

  @doc false
  def message_store, do: Application.fetch_env!(:palee, :email_message_store)

  @doc false
  def sender, do: Application.fetch_env!(:palee, :email_sender)

  @doc false
  # A Message-ID on the sender's domain, chosen at enqueue so every retry
  # carries the same one (Palee.Mailer keeps an existing Message-ID).
  def new_message_id do
    :palee
    |> Application.fetch_env!(:mail_from)
    |> Keyword.fetch!(:address)
    |> Palee.Mailer.domain_of()
    |> Palee.Mailer.message_id()
  end

  @doc false
  def emit(event, %Message{} = message, extra \\ %{}) do
    :telemetry.execute(
      [:palee, :email, event],
      %{count: 1},
      Map.merge(%{message_id: message.id, kind: message.kind, category: message.category}, extra)
    )
  end

  defp summary(%Message{} = message) do
    Map.take(message, [
      :id,
      :kind,
      :category,
      :status,
      :attempts,
      :last_error,
      :scheduled_at,
      :sent_at,
      :inserted_at,
      :idempotency_key
    ])
  end
end
