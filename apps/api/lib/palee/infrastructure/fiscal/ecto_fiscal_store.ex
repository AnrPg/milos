defmodule Palee.Infrastructure.Fiscal.EctoFiscalStore do
  @moduledoc "Ecto adapter of the Fiscal store (ADR-240–242)."

  @behaviour Palee.Fiscal.Ports.FiscalStore

  import Ecto.Query

  alias Palee.Fiscal.{
    AuthorityConnection,
    BusinessIdentity,
    Document,
    DocumentLine,
    ExportSetting,
    JournalEntry,
    JournalHead,
    PeriodClosingRecord,
    SalesTaxRate,
    Sequence,
    Transmission,
    TransmissionAttempt
  }

  alias Palee.Fiscal.Domain.JournalChain
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

  # ── Identity ──────────────────────────────────────────────────────────────

  @impl true
  def get_identity(%{organization_id: organization_id}) do
    BusinessIdentity
    |> where([i], i.organization_id == ^organization_id)
    |> Repo.one()
    |> identity_map()
  end

  @impl true
  def save_identity(%{organization_id: organization_id}, attrs) do
    case Repo.one(from i in BusinessIdentity, where: i.organization_id == ^organization_id) do
      nil -> %BusinessIdentity{organization_id: organization_id}
      identity -> identity
    end
    |> BusinessIdentity.changeset(attrs)
    |> Repo.insert_or_update()
    |> case do
      {:ok, identity} -> {:ok, identity_map(identity)}
      error -> error
    end
  end

  defp identity_map(nil), do: nil

  defp identity_map(%BusinessIdentity{} = identity) do
    identity
    |> Map.take([:id, :organization_id, :inserted_at, :updated_at | BusinessIdentity.fields()])
  end

  # ── Journal ───────────────────────────────────────────────────────────────

  @impl true
  def lock_journal_head(%{organization_id: organization_id}) do
    Repo.insert_all(
      JournalHead,
      [
        %{
          id: Ecto.UUID.generate(),
          organization_id: organization_id,
          position: 0,
          hash: JournalChain.genesis_hash(),
          inserted_at: now(),
          updated_at: now()
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:organization_id]
    )

    head =
      JournalHead
      |> where([h], h.organization_id == ^organization_id)
      |> lock("FOR UPDATE")
      |> Repo.one!()

    %{position: head.position, hash: head.hash}
  end

  @impl true
  def insert_journal_entry(%{organization_id: organization_id}, entry) do
    with {:ok, row} <- entry |> JournalEntry.insert_changeset() |> Repo.insert() do
      {1, _} =
        JournalHead
        |> where(
          [h],
          h.organization_id == ^organization_id and h.position == ^(entry.position - 1)
        )
        |> Repo.update_all(set: [position: entry.position, hash: entry.hash, updated_at: now()])

      {:ok, entry_map(row)}
    end
  end

  @impl true
  def list_journal_entries(%{organization_id: organization_id}, opts) do
    JournalEntry
    |> where([e], e.organization_id == ^organization_id)
    |> where([e], e.position > ^Map.get(opts, :after_position, 0))
    |> then(fn query ->
      case opts[:from] do
        nil -> query
        from -> where(query, [e], e.occurred_at >= ^from)
      end
    end)
    |> then(fn query ->
      case opts[:to] do
        nil -> query
        to -> where(query, [e], e.occurred_at < ^to)
      end
    end)
    |> order_by([e], asc: e.position)
    |> limit(^Map.get(opts, :limit, 1_000))
    |> Repo.all()
    |> Enum.map(&entry_map/1)
  end

  defp entry_map(%JournalEntry{} = entry) do
    Map.take(entry, [
      :id,
      :organization_id,
      :position,
      :event_type,
      :subject_type,
      :subject_id,
      :actor_id,
      :occurred_at,
      :payload,
      :previous_hash,
      :hash,
      :signature,
      :signature_key_id
    ])
  end

  # ── Documents ─────────────────────────────────────────────────────────────

  @impl true
  def next_sequence(%{organization_id: organization_id}, series) do
    Repo.insert_all(
      Sequence,
      [
        %{
          id: Ecto.UUID.generate(),
          organization_id: organization_id,
          series: series,
          last_value: 0,
          inserted_at: now(),
          updated_at: now()
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:organization_id, :series]
    )

    sequence =
      Sequence
      |> where([s], s.organization_id == ^organization_id and s.series == ^series)
      |> lock("FOR UPDATE")
      |> Repo.one!()

    next = sequence.last_value + 1

    {1, _} =
      Sequence
      |> where([s], s.id == ^sequence.id)
      |> Repo.update_all(set: [last_value: next, updated_at: now()])

    next
  end

  @impl true
  def insert_document(_context, document, lines) do
    with {:ok, row} <- document |> Document.insert_changeset() |> Repo.insert(),
         {:ok, line_rows} <- insert_lines(row.id, lines) do
      {:ok, document_map(%{row | lines: line_rows})}
    end
  end

  defp insert_lines(document_id, lines) do
    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, acc} ->
      case line
           |> Map.put(:document_id, document_id)
           |> DocumentLine.insert_changeset()
           |> Repo.insert() do
        {:ok, row} -> {:cont, {:ok, [row | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.sort_by(rows, & &1.position)}
      error -> error
    end
  end

  @impl true
  def get_document(%{organization_id: organization_id}, id, opts) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Document{} = document <-
           Document
           |> where([d], d.organization_id == ^organization_id and d.id == ^id)
           |> then(fn query -> if opts[:lock], do: lock(query, "FOR UPDATE"), else: query end)
           |> Repo.one() do
      document
      |> Repo.preload(lines: from(l in DocumentLine, order_by: l.position))
      |> document_map()
    else
      _missing -> nil
    end
  end

  @impl true
  def get_document_by_idempotency_key(%{organization_id: organization_id}, key) do
    Document
    |> where([d], d.organization_id == ^organization_id and d.idempotency_key == ^key)
    |> Repo.one()
    |> case do
      nil ->
        nil

      document ->
        document
        |> Repo.preload(lines: from(l in DocumentLine, order_by: l.position))
        |> document_map()
    end
  end

  @impl true
  def list_documents(%{organization_id: organization_id}, filters) do
    query =
      Document
      |> where([d], d.organization_id == ^organization_id)
      |> filter(:kind, filters[:kind])
      |> filter(:from, filters[:from])
      |> filter(:to, filters[:to])
      |> filter(:number, filters[:number])
      |> filter(:corrects, filters[:corrects_document_id])

    limit = filters |> Map.get(:limit, 50) |> min(@max_page) |> max(1)
    offset = filters |> Map.get(:offset, 0) |> max(0)

    documents =
      query
      |> order_by([d], desc: d.issued_at, desc: d.sequence)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()
      |> Enum.map(&document_map(%{&1 | lines: []}))

    %{documents: documents, total: Repo.aggregate(query, :count)}
  end

  defp filter(query, _key, nil), do: query
  defp filter(query, :kind, kind), do: where(query, [d], d.kind == ^kind)
  defp filter(query, :from, from), do: where(query, [d], d.issue_date >= ^from)
  defp filter(query, :to, to), do: where(query, [d], d.issue_date <= ^to)

  defp filter(query, :number, number),
    do: where(query, [d], ilike(d.number, ^"%#{String.replace(number, ~r/[%_\\]/, "")}%"))

  defp filter(query, :corrects, id), do: where(query, [d], d.corrects_document_id == ^id)

  @impl true
  def credited_lines(%{organization_id: organization_id}, id) do
    DocumentLine
    |> join(:inner, [l], d in Document, on: d.id == l.document_id)
    |> where([l, d], d.organization_id == ^organization_id and d.corrects_document_id == ^id)
    |> where([l], not is_nil(l.corrects_position))
    |> group_by([l], l.corrects_position)
    |> select(
      [l],
      {l.corrects_position, %{quantity: sum(l.quantity), amount_cents: sum(l.amount_cents)}}
    )
    |> Repo.all()
    |> Map.new(fn {position, totals} ->
      {position, %{quantity: to_int(totals.quantity), amount_cents: to_int(totals.amount_cents)}}
    end)
  end

  @impl true
  def documents_between(%{organization_id: organization_id}, from, to) do
    Document
    |> where(
      [d],
      d.organization_id == ^organization_id and d.issue_date >= ^from and d.issue_date <= ^to
    )
    |> order_by([d], asc: d.journal_position)
    |> Repo.all()
    |> Enum.map(&document_map(%{&1 | lines: []}))
  end

  @impl true
  def first_issue_date(%{organization_id: organization_id}) do
    Document
    |> where([d], d.organization_id == ^organization_id)
    |> select([d], min(d.issue_date))
    |> Repo.one()
  end

  defp document_map(%Document{} = document) do
    lines =
      case document.lines do
        %Ecto.Association.NotLoaded{} -> []
        lines -> Enum.map(lines, &line_map/1)
      end

    document
    |> Map.from_struct()
    |> Map.drop([:__meta__])
    |> Map.put(:lines, lines)
  end

  defp line_map(%DocumentLine{} = line), do: line |> Map.from_struct() |> Map.drop([:__meta__])

  # ── Closings ──────────────────────────────────────────────────────────────

  @impl true
  def latest_closings(%{organization_id: organization_id}) do
    PeriodClosingRecord
    |> where([c], c.organization_id == ^organization_id)
    |> distinct([c], c.period_kind)
    |> order_by([c], asc: c.period_kind, desc: c.period_end)
    |> Repo.all()
    |> Map.new(&{&1.period_kind, closing_map(&1)})
  end

  @impl true
  def insert_closing(_context, closing) do
    with {:ok, row} <- closing |> PeriodClosingRecord.insert_changeset() |> Repo.insert() do
      {:ok, closing_map(row)}
    end
  end

  @impl true
  def list_closings(%{organization_id: organization_id}, filters) do
    PeriodClosingRecord
    |> where([c], c.organization_id == ^organization_id)
    |> then(fn query ->
      case filters[:kind] do
        nil -> query
        kind -> where(query, [c], c.period_kind == ^kind)
      end
    end)
    |> then(fn query ->
      case filters[:from] do
        nil -> query
        from -> where(query, [c], c.period_end >= ^from)
      end
    end)
    |> then(fn query ->
      case filters[:to] do
        nil -> query
        to -> where(query, [c], c.period_start <= ^to)
      end
    end)
    |> order_by([c], desc: c.period_start, asc: c.period_kind)
    |> limit(^min(Map.get(filters, :limit, 100), 2_000))
    |> Repo.all()
    |> Enum.map(&closing_map/1)
  end

  defp closing_map(%PeriodClosingRecord{} = closing),
    do: closing |> Map.from_struct() |> Map.drop([:__meta__])

  # ── Purge ─────────────────────────────────────────────────────────────────

  @impl true
  def purge(%{organization_id: organization_id}) do
    Repo.transaction(fn ->
      Repo.query!("SELECT set_config('palee.fiscal_purge', 'on', true)")

      Map.new(
        [
          {"fiscal_export_settings", ExportSetting},
          {"fiscal_sales_tax_rates", SalesTaxRate},
          {"fiscal_till_signature_attempts", Palee.Fiscal.TillSignatureAttempt},
          {"fiscal_till_signatures", Palee.Fiscal.TillSignature},
          {"fiscal_till_connections", Palee.Fiscal.TillConnection},
          {"fiscal_einvoice_attempts", Palee.Fiscal.EInvoiceAttempt},
          {"fiscal_einvoice_submissions", Palee.Fiscal.EInvoiceSubmission},
          {"fiscal_network_connections", Palee.Fiscal.NetworkConnection},
          {"fiscal_transmission_attempts", TransmissionAttempt},
          {"fiscal_transmissions", Transmission},
          {"fiscal_authority_connections", AuthorityConnection},
          {"fiscal_period_closings", PeriodClosingRecord},
          {"fiscal_document_lines", DocumentLine},
          {"fiscal_documents", Document},
          {"fiscal_journal_entries", JournalEntry},
          {"fiscal_journal_heads", JournalHead},
          {"fiscal_sequences", Sequence},
          {"fiscal_business_identities", BusinessIdentity}
        ],
        fn {table, schema} ->
          {count, _} =
            schema |> where([r], r.organization_id == ^organization_id) |> Repo.delete_all()

          {table, count}
        end
      )
    end)
  end

  defp to_int(nil), do: 0
  defp to_int(%Decimal{} = value), do: Decimal.to_integer(value)
  defp to_int(value) when is_integer(value), do: value

  defp now, do: DateTime.utc_now()
end
