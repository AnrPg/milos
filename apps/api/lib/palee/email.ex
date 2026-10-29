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

  ADR-212 adds what happens after sending: the provider's webhook
  (`handle_provider_events/3`) turns hard bounces and complaints into
  suppressions and marks messages `bounced`/`complained` (telemetry
  `:bounced`, `:complained`, `:delivered`, and `[:palee, :email,
  :provider_event]`); transactional mail carries a one-click unsubscribe
  link (`unsubscribe_url/3`, `unsubscribe/1`); `deliverable?/1` and
  `suppression/1` let screens say "this address bounced"; `purge/1` is the
  retention sweep and `sending_stats/1` and `smtp_key_status/1` feed the
  alarms.
  """

  alias Palee.Email.Commands.{DeliverEmail, EnqueueEmail, HandleProviderEvents, Unsubscribe}
  alias Palee.Email.Domain.{Address, KeyExpiry, RetentionPolicy, SendingPolicy}
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
    * `:attachments` - files to send with it (ADR-265):
      `[%{filename, content_type: "application/pdf", data}]`, at most 5 MB
      in all; they are encrypted with the body and cleared with it
      (`{:error, :invalid_attachment | :attachment_too_large}` otherwise);
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
  "suppressed" | "bounced" | "complained"`), `attempts`, `last_error`,
  `scheduled_at`, `sent_at`, `delivered_at`, `inserted_at`,
  `idempotency_key`; or `{:error, :not_found}`.
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

  # -- ADR-212: deliverability ------------------------------------------------

  @doc """
  Whether mail to `address` can be sent at all: it is a valid address and
  not suppressed (a hard bounce, a complaint or a manual block). An opt-out
  from one transactional kind does not make an address undeliverable.
  Screens use it to say "this address bounced".
  """
  @spec deliverable?(String.t() | nil) :: boolean()
  def deliverable?(address), do: Address.valid?(address) and not suppressed?(address)

  @doc """
  Why `address` is suppressed: `%{reason: "bounce" | "complaint" | "manual",
  since: DateTime}`, or nil when it is not.
  """
  @spec suppression(String.t() | nil) :: %{reason: String.t(), since: DateTime.t()} | nil
  def suppression(address) do
    with digest when is_binary(digest) <- Address.digest(address),
         %Palee.Email.Suppression{} = row <- message_store().suppression(digest) do
      %{reason: row.reason, since: row.inserted_at}
    else
      _none -> nil
    end
  end

  @doc """
  The addresses of `addresses` that are suppressed, normalised (trimmed,
  lower case), in one query: for a list of invitations or people.
  """
  @spec undeliverable([String.t()]) :: MapSet.t(String.t())
  def undeliverable(addresses) when is_list(addresses) do
    by_digest =
      addresses
      |> Enum.filter(&is_binary/1)
      |> Map.new(fn address ->
        {Address.digest(address), String.downcase(String.trim(address))}
      end)
      |> Map.delete(nil)

    by_digest
    |> Map.keys()
    |> message_store().suppressed_digests()
    |> MapSet.new(&Map.fetch!(by_digest, &1))
  end

  @doc "Whether `address` unsubscribed from transactional mail of `kind`."
  @spec opted_out?(String.t(), atom() | String.t()) :: boolean()
  def opted_out?(address, kind) do
    case Address.digest(address) do
      nil -> false
      digest -> message_store().opted_out?(digest, to_string(kind))
    end
  end

  @doc """
  Applies one webhook body of the mail provider (only `:brevo`): bounces
  and complaints suppress the address, deliveries set `delivered_at`.
  `{:ok, %{applied, duplicate, unmatched}}` or `{:error, :invalid_payload}`.
  """
  def handle_provider_events(provider, payload, now \\ DateTime.utc_now()),
    do: HandleProviderEvents.call(provider, payload, now)

  @doc "The signed one-click unsubscribe URL of `kind` mail to `address` (ADR-212)."
  defdelegate unsubscribe_url(address, kind, locale), to: Unsubscribe, as: :url

  @doc "What an unsubscribe token is for (`%{kind, locale}`), without acting on it."
  defdelegate unsubscribe_info(token), to: Unsubscribe, as: :peek

  @doc "Opts the token's address out of its kind of mail."
  defdelegate unsubscribe(token), to: Unsubscribe, as: :call

  @doc """
  The retention sweep (ADR-212): deletes messages older than 90 days (not
  ones still queued or deferred) with their provider events, and link
  tokens used or expired more than 7 days ago. Returns the counts.
  """
  def purge(now \\ DateTime.utc_now()) do
    messages =
      message_store().purge_messages(
        RetentionPolicy.messages_before(now),
        RetentionPolicy.pending_statuses()
      )

    link_tokens =
      Application.fetch_env!(:palee, :email_link_token_store).purge_spent(
        RetentionPolicy.link_tokens_before(now)
      )

    %{messages: messages, link_tokens: link_tokens}
  end

  @doc """
  Today's sending against the budget, for the alarm (ADR-212):
  `%{sent_today, daily_budget, hard_cap, deferred}`.
  """
  def sending_stats(now \\ DateTime.utc_now()) do
    budget = budget()

    %{
      sent_today: message_store().count_sent_since(SendingPolicy.day_start(now)),
      daily_budget: budget.daily_budget,
      hard_cap: budget.hard_cap,
      deferred: message_store().count_status("deferred")
    }
  end

  @doc """
  The SMTP key's expiry (`SMTP_KEY_EXPIRES_ON`) on `today`:
  `%{expires_on, days_left, state}` with `state` `:unknown` (not set),
  `:ok`, `{:expiring, days}` (30 days or fewer) or `:expired`.
  """
  def smtp_key_status(today \\ Date.utc_today()) do
    expires_on = Application.get_env(:palee, :smtp_key_expires_on)

    %{
      expires_on: expires_on,
      days_left: expires_on && KeyExpiry.days_left(expires_on, today),
      state: KeyExpiry.state(expires_on, today)
    }
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
      :delivered_at,
      :inserted_at,
      :idempotency_key
    ])
  end
end
