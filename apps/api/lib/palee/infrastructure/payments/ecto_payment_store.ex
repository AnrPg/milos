defmodule Palee.Infrastructure.Payments.EctoPaymentStore do
  @moduledoc "Ecto adapter of the payment store (ADR-246/247)."

  @behaviour Palee.Payments.Ports.PaymentStore

  import Ecto.Query

  alias Palee.Payments.{Account, Intent, Refund, SavedMethod, WebhookEvent}
  alias Palee.Payments.Domain.IntentPolicy
  alias Palee.Repo

  @max_page 200

  @impl true
  def transaction(_context, fun) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # ── Account ─────────────────────────────────────────────────────────────

  @impl true
  def get_account(%{organization_id: organization_id}) do
    Account
    |> where([a], a.organization_id == ^organization_id)
    |> Repo.one()
    |> account_map()
  end

  @impl true
  def get_account(%{organization_id: organization_id}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        Account
        |> where([a], a.organization_id == ^organization_id and a.id == ^id)
        |> Repo.one()
        |> account_map()

      :error ->
        nil
    end
  end

  @impl true
  def save_account(%{organization_id: organization_id}, attrs) do
    # Only a given `credentials` is written: a status or options change keeps them.
    attrs =
      case attrs do
        %{credentials: map} when is_map(map) -> %{attrs | credentials: Jason.encode!(map)}
        _other -> attrs
      end

    case Repo.one(from a in Account, where: a.organization_id == ^organization_id) do
      nil -> %Account{organization_id: organization_id}
      account -> account
    end
    |> Account.changeset(attrs)
    |> Repo.insert_or_update()
    |> case do
      {:ok, account} -> {:ok, account_map(account)}
      error -> error
    end
  end

  @impl true
  def set_account_status(%{organization_id: organization_id}, id, status, error, now) do
    Account
    |> where([a], a.organization_id == ^organization_id and a.id == ^id)
    |> Repo.update_all(
      set: [status: status, last_error: error, checked_at: now, updated_at: DateTime.utc_now()]
    )

    :ok
  end

  defp account_map(nil), do: nil

  defp account_map(%Account{} = account) do
    credentials =
      case account.credentials && Jason.decode(account.credentials) do
        {:ok, map} when is_map(map) -> map
        _missing -> %{}
      end

    account |> plain() |> Map.put(:credentials, credentials)
  end

  # ── Intents ─────────────────────────────────────────────────────────────

  @impl true
  def insert_intent(_context, attrs) do
    case %Intent{} |> Intent.changeset(attrs) |> Repo.insert() do
      {:ok, intent} ->
        {:ok, plain(intent)}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if Keyword.has_key?(errors, :organization_id),
          do: {:error, :duplicate_idempotency_key},
          else: {:error, changeset}
    end
  end

  @impl true
  def get_intent(%{organization_id: organization_id}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        Intent
        |> where([i], i.organization_id == ^organization_id and i.id == ^id)
        |> Repo.one()
        |> plain()

      :error ->
        nil
    end
  end

  @impl true
  def get_intent_by_key(%{organization_id: organization_id}, key) do
    Intent
    |> where([i], i.organization_id == ^organization_id and i.idempotency_key == ^key)
    |> Repo.one()
    |> plain()
  end

  @impl true
  def get_intent_by_ref(%{organization_id: organization_id}, provider, ref) do
    Intent
    |> where([i], i.organization_id == ^organization_id and i.provider == ^provider)
    |> where([i], i.provider_ref == ^ref or i.provider_transaction_id == ^ref)
    |> order_by([i], desc: i.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> plain()
  end

  @impl true
  def update_intent(%{organization_id: organization_id}, id, changes) do
    case Repo.one(
           from i in Intent,
             where: i.organization_id == ^organization_id and i.id == ^id,
             lock: "FOR UPDATE"
         ) do
      nil ->
        {:error, :not_found}

      intent ->
        case intent |> Intent.changeset(changes) |> Repo.update() do
          {:ok, updated} -> {:ok, plain(updated)}
          error -> error
        end
    end
  end

  @impl true
  def claim_due(%{organization_id: organization_id}, which, %DateTime{} = now, limit) do
    stale = DateTime.add(now, -IntentPolicy.lease_seconds(), :second)
    statuses = IntentPolicy.open_statuses()

    Intent
    |> where([i], i.organization_id == ^organization_id and i.status in ^statuses)
    |> where([i], is_nil(i.claimed_at) or i.claimed_at < ^stale)
    |> by_which(which, fn query -> where(query, [i], i.next_attempt_at <= ^now) end)
    |> lease(now, limit)
  end

  @impl true
  def claim_fulfilments(%{organization_id: organization_id}, which, %DateTime{} = now, limit) do
    stale = DateTime.add(now, -IntentPolicy.lease_seconds(), :second)

    Intent
    |> where([i], i.organization_id == ^organization_id and i.status == "succeeded")
    |> where([i], i.fulfilment_status == "pending")
    |> where([i], is_nil(i.claimed_at) or i.claimed_at < ^stale)
    |> by_which(which, fn query ->
      where(query, [i], is_nil(i.next_attempt_at) or i.next_attempt_at <= ^now)
    end)
    |> lease(now, limit)
  end

  defp by_which(query, :due, due), do: due.(query)
  defp by_which(query, id, _due), do: where(query, [i], i.id == ^id)

  defp lease(query, now, limit) do
    ids =
      query
      |> order_by([i], asc_nulls_first: i.next_attempt_at)
      |> limit(^limit)
      |> lock("FOR UPDATE SKIP LOCKED")
      |> select([i], i.id)

    {_count, rows} =
      Intent
      |> where([i], i.id in subquery(ids))
      |> select([i], i)
      |> Repo.update_all(set: [claimed_at: now, updated_at: DateTime.utc_now()])

    Enum.map(rows, &plain/1)
  end

  @impl true
  def list_intents(%{organization_id: organization_id}, filters) do
    query =
      from(i in Intent, as: :intent)
      |> where([i], i.organization_id == ^organization_id)
      |> filter(:status, filters[:status])
      |> filter(:user_id, filters[:user_id])
      |> filter(:purpose_type, filters[:purpose_type])
      |> filter(:purpose_id, filters[:purpose_id])
      |> attention(filters[:attention])

    %{
      intents:
        query
        |> order_by([i], desc: i.inserted_at, desc: i.id)
        |> limit(^min(filters[:limit] || 50, @max_page))
        |> offset(^(filters[:offset] || 0))
        |> Repo.all()
        |> Enum.map(&plain/1),
      total: Repo.aggregate(query, :count)
    }
  end

  # ADR-260: saved-card charges a person may need to act on: declined and
  # waiting for a retry, or failed for good, not closed by staff and not
  # paid since by another online payment for the same purpose.
  defp attention(query, true) do
    query
    |> where([i], i.initiation == "merchant" and is_nil(i.attention_resolved_at))
    |> where(
      [i],
      i.status == "failed" or
        (i.status == "scheduled" and
           fragment("COALESCE((?->>'declines')::int, 0) > 0", i.consent))
    )
    |> where(
      [i],
      not exists(
        from(paid in Intent,
          where:
            paid.organization_id == parent_as(:intent).organization_id and
              paid.purpose_type == parent_as(:intent).purpose_type and
              paid.purpose_id == parent_as(:intent).purpose_id and
              paid.status == "succeeded" and
              paid.inserted_at > parent_as(:intent).inserted_at
        )
      )
    )
  end

  defp attention(query, _no), do: query

  defp filter(query, _field, nil), do: query
  defp filter(query, field, value), do: where(query, [i], field(i, ^field) == ^value)

  @impl true
  def add_refunded(%{organization_id: organization_id}, id, amount) do
    Intent
    |> where([i], i.organization_id == ^organization_id and i.id == ^id)
    |> where([i], i.refunded_cents + ^amount <= i.amount_cents)
    |> select([i], i)
    |> Repo.update_all(inc: [refunded_cents: amount], set: [updated_at: DateTime.utc_now()])
    |> case do
      {1, [intent]} -> {:ok, plain(intent)}
      {0, _rows} -> {:error, :refund_exceeds_payment}
    end
  end

  # ── Saved methods ───────────────────────────────────────────────────────

  @impl true
  def upsert_method(%{organization_id: organization_id}, attrs) do
    existing =
      Repo.one(
        from m in SavedMethod,
          where:
            m.organization_id == ^organization_id and m.account_id == ^attrs.account_id and
              m.token_digest == ^attrs.token_digest
      )

    (existing || %SavedMethod{organization_id: organization_id})
    |> SavedMethod.changeset(attrs)
    |> Repo.insert_or_update()
    |> case do
      {:ok, method} -> {:ok, plain(method)}
      error -> error
    end
  end

  @impl true
  def get_method(%{organization_id: organization_id}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        SavedMethod
        |> where([m], m.organization_id == ^organization_id and m.id == ^id)
        |> Repo.one()
        |> plain()

      :error ->
        nil
    end
  end

  @impl true
  def list_methods(%{organization_id: organization_id}, user_id) do
    SavedMethod
    |> where([m], m.organization_id == ^organization_id and m.user_id == ^user_id)
    |> where([m], m.status != "revoked")
    |> order_by([m], desc: m.autopay, desc: m.inserted_at)
    |> Repo.all()
    |> Enum.map(&plain/1)
  end

  @impl true
  def update_method(%{organization_id: organization_id}, id, changes) do
    case Repo.one(
           from m in SavedMethod, where: m.organization_id == ^organization_id and m.id == ^id
         ) do
      nil ->
        {:error, :not_found}

      method ->
        case method |> SavedMethod.changeset(changes) |> Repo.update() do
          {:ok, updated} -> {:ok, plain(updated)}
          error -> error
        end
    end
  end

  @impl true
  def clear_autopay(%{organization_id: organization_id}, user_id, except) do
    SavedMethod
    |> where([m], m.organization_id == ^organization_id and m.user_id == ^user_id)
    |> where([m], m.id != ^except and m.autopay)
    |> Repo.update_all(set: [autopay: false, updated_at: DateTime.utc_now()])

    :ok
  end

  @impl true
  def autopay_methods(%{organization_id: organization_id}) do
    SavedMethod
    |> where([m], m.organization_id == ^organization_id and m.autopay and m.status == "active")
    |> Repo.all()
    |> Enum.map(&plain/1)
  end

  # ── Refunds ─────────────────────────────────────────────────────────────

  @impl true
  def insert_refund(_context, attrs) do
    case %Refund{} |> Refund.changeset(attrs) |> Repo.insert() do
      {:ok, refund} -> {:ok, plain(refund)}
      error -> error
    end
  end

  @impl true
  def get_refund_by_key(%{organization_id: organization_id}, key) do
    Refund
    |> where([r], r.organization_id == ^organization_id and r.idempotency_key == ^key)
    |> Repo.one()
    |> plain()
  end

  @impl true
  def update_refund(%{organization_id: organization_id}, id, changes) do
    case Repo.one(from r in Refund, where: r.organization_id == ^organization_id and r.id == ^id) do
      nil ->
        {:error, :not_found}

      refund ->
        case refund |> Refund.changeset(changes) |> Repo.update() do
          {:ok, updated} -> {:ok, plain(updated)}
          error -> error
        end
    end
  end

  @impl true
  def list_refunds(%{organization_id: organization_id}, intent_id) do
    Refund
    |> where([r], r.organization_id == ^organization_id and r.intent_id == ^intent_id)
    |> order_by([r], asc: r.inserted_at)
    |> Repo.all()
    |> Enum.map(&plain/1)
  end

  # ── Webhooks ────────────────────────────────────────────────────────────

  @impl true
  def record_webhook_event(%{organization_id: organization_id}, attrs) do
    now = DateTime.utc_now()

    row =
      attrs
      |> Map.take([:account_id, :provider, :event_id, :event_type, :reference, :received_at])
      |> Map.merge(%{
        id: Ecto.UUID.generate(),
        organization_id: organization_id,
        status: "received",
        inserted_at: now,
        updated_at: now
      })

    # A redelivered event (same account and event id) inserts nothing.
    case Repo.insert_all(WebhookEvent, [row],
           on_conflict: :nothing,
           conflict_target: [:account_id, :event_id],
           returning: true
         ) do
      {1, [event]} ->
        {:ok, plain(event)}

      {0, []} ->
        {:duplicate,
         WebhookEvent
         |> where([e], e.organization_id == ^organization_id)
         |> where([e], e.account_id == ^attrs.account_id and e.event_id == ^attrs.event_id)
         |> Repo.one()
         |> plain()}
    end
  end

  @impl true
  def finish_webhook_event(%{organization_id: organization_id}, id, status, error, now) do
    WebhookEvent
    |> where([e], e.organization_id == ^organization_id and e.id == ^id)
    |> Repo.update_all(
      set: [status: status, error: error, processed_at: now, updated_at: DateTime.utc_now()]
    )

    :ok
  end

  defp plain(nil), do: nil
  defp plain(struct), do: struct |> Map.from_struct() |> Map.drop([:__meta__])
end
