defmodule Palee.Fiscal do
  @moduledoc """
  The Fiscal bounded context (ADR-240–242): what the law asks of a sale.

    * the business's legal identity and its country profile;
    * immutable fiscal documents (receipts, invoices, credit notes) with
      gapless series and VAT by rate group;
    * the inalterable, signed journal, period closings and the audit archive.

  Fiscal never reads other contexts' tables: callers hand it sale lines.
  Use cases that need other contexts (the gym's local date, permissions,
  Finance) live in `Palee.Application.Fiscal.*`.
  """

  alias Palee.Fiscal.Domain.{
    BusinessIdentityPolicy,
    CanonicalJson,
    CountryProfile,
    DocumentSeries,
    FiscalDocumentPolicy,
    JournalChain,
    PeriodClosing,
    TenantDataPolicy,
    VatRates
  }

  alias Palee.Fiscal.{EInvoicing, FiscalStore, Reporting, TillSigning}

  @verify_batch 1_000

  # ── Ports ───────────────────────────────────────────────────────────────

  @doc "The configured journal signer (`Fiscal.Ports.JournalSigner`)."
  def signer, do: Application.fetch_env!(:palee, :fiscal_journal_signer)

  # ── Country profiles ────────────────────────────────────────────────────

  @doc "Supported countries with their public profile and tax categories."
  def countries do
    Enum.map(CountryProfile.countries(), fn country ->
      country
      |> CountryProfile.fetch!()
      |> CountryProfile.public()
      |> Map.put(:tax_categories, VatRates.categories(country))
    end)
  end

  defdelegate vat_schemes(), to: BusinessIdentityPolicy
  defdelegate document_kinds(), to: FiscalDocumentPolicy, as: :kinds
  defdelegate payment_methods(), to: FiscalDocumentPolicy
  defdelegate credit_reasons(), to: FiscalDocumentPolicy
  defdelegate credit_reason(reason), to: FiscalDocumentPolicy

  # ── Identity ────────────────────────────────────────────────────────────

  @doc """
  `%{identity, profile, missing, complete}`: the saved identity (nil when
  none), its country's public profile and the fields still missing.
  """
  def identity_status(context) do
    identity = FiscalStore.get_identity(context)
    status(identity)
  end

  defp status(nil), do: %{identity: nil, profile: nil, missing: [:country_code], complete: false}

  defp status(identity) do
    profile = CountryProfile.fetch!(identity.country_code)
    missing = CountryProfile.missing_fields(profile, identity)

    %{
      identity: identity,
      profile:
        CountryProfile.public(profile)
        |> Map.put(:tax_categories, VatRates.categories(identity.country_code)),
      missing: missing,
      complete: missing == []
    }
  end

  @doc """
  Saves (part of) the identity and journals the fields that changed.
  `{:ok, status}` or `{:error, {:invalid_fields, errors}}`.
  """
  def save_identity(context, changes, actor_id, %DateTime{} = now) do
    FiscalStore.transaction(context, fn ->
      before = FiscalStore.get_identity(context) || %{}

      with {:ok, attrs} <- BusinessIdentityPolicy.validate(before, changes),
           {:ok, saved} <-
             FiscalStore.save_identity(context, Map.put(attrs, :updated_by_id, actor_id)) do
        changed = BusinessIdentityPolicy.changed_fields(before, saved)

        if changed == [] do
          {:ok, status(saved)}
        else
          payload = %{
            changed: changed,
            identity: Map.take(saved, BusinessIdentityPolicy.fields() ++ [:currency])
          }

          with {:ok, _entry} <-
                 append(context, %{
                   event_type: "identity_saved",
                   subject_type: "business_identity",
                   subject_id: saved.id,
                   actor_id: actor_id,
                   occurred_at: now,
                   payload: payload
                 }) do
            {:ok, status(saved)}
          end
        end
      end
    end)
  end

  # ── Documents ───────────────────────────────────────────────────────────

  @doc """
  Issues a receipt or invoice (ADR-241). `request` as in
  `FiscalDocumentPolicy`; `issue_date` is the gym-local date. Idempotent by
  `idempotency_key`: a retry returns `{:ok, document, :replayed}`.
  """
  def issue(context, request, actor_id, %DateTime{} = now) do
    request_hash = request |> Map.drop([:issue_date]) |> hash_term()

    FiscalStore.transaction(context, fn ->
      case replay(context, request[:idempotency_key], request_hash) do
        {:ok, document} ->
          {:ok, {document, :replayed}}

        {:error, reason} ->
          {:error, reason}

        :new ->
          with identity when is_map(identity) <-
                 FiscalStore.get_identity(context) || {:error, :fiscal_identity_missing},
               {:ok, document} <- FiscalDocumentPolicy.build(identity, request),
               {:ok, saved} <-
                 store_document(
                   context,
                   document,
                   identity.branch_code,
                   request_hash,
                   actor_id,
                   now
                 ) do
            {:ok, {saved, :issued}}
          end
      end
    end)
    |> unwrap_issue()
  end

  @doc """
  Issues a credit note correcting `document_id` by `requested` (`:all`,
  `[%{position, quantity}]` or `%{amount_cents: n}`). Idempotent by
  `idempotency_key`.

  Options: `:reason` – why (ADR-265, one of
  `FiscalDocumentPolicy.credit_reasons/0`); it is stored on the note,
  printed on it, hashed with its content and journaled.
  """
  def credit(
        context,
        document_id,
        requested,
        %Date{} = issue_date,
        idempotency_key,
        actor_id,
        %DateTime{} = now,
        opts \\ []
      ) do
    with {:ok, reason} <- FiscalDocumentPolicy.credit_reason(Keyword.get(opts, :reason)) do
      request = %{
        document_id: document_id,
        requested: requested,
        issue_date: issue_date,
        idempotency_key: idempotency_key,
        reason: reason
      }

      credit_note(context, request, actor_id, now)
    end
  end

  defp credit_note(context, request, actor_id, now) do
    %{
      document_id: document_id,
      requested: requested,
      issue_date: issue_date,
      idempotency_key: idempotency_key,
      reason: reason
    } = request

    # A note without a reason keeps the request hash it had before ADR-265.
    request_hash =
      %{credit: document_id, requested: requested}
      |> put_present(:reason, reason)
      |> hash_term()

    FiscalStore.transaction(context, fn ->
      case replay(context, idempotency_key, request_hash) do
        {:ok, document} ->
          {:ok, {document, :replayed}}

        {:error, reason} ->
          {:error, reason}

        :new ->
          with original when is_map(original) <-
                 FiscalStore.get_document(context, document_id, lock: true) ||
                   {:error, :not_found},
               identity when is_map(identity) <-
                 FiscalStore.get_identity(context) || {:error, :fiscal_identity_missing},
               credited = FiscalStore.credited_lines(context, original.id),
               {:ok, note} <-
                 FiscalDocumentPolicy.credit_note(original, credited, requested, issue_date),
               note =
                 Map.merge(note, %{idempotency_key: idempotency_key, credit_reason: reason}),
               {:ok, saved} <-
                 store_document(context, note, identity.branch_code, request_hash, actor_id, now) do
            {:ok, {saved, :issued}}
          end
      end
    end)
    |> unwrap_issue()
  end

  @doc """
  The credit note `credit/8` would issue now for `requested`, without
  issuing it: `{:ok, note}` (with totals and lines) or `{:error, reason}`.
  ADR-265 refunds exactly its `gross_cents` before the refund issues it.
  """
  def credit_preview(context, document_id, requested, %Date{} = issue_date) do
    with original when is_map(original) <-
           FiscalStore.get_document(context, document_id, []) || {:error, :not_found} do
      credited = FiscalStore.credited_lines(context, original.id)
      FiscalDocumentPolicy.credit_note(original, credited, requested, issue_date)
    end
  end

  defp unwrap_issue({:ok, {document, mode}}), do: {:ok, document, mode}
  defp unwrap_issue(error), do: error

  defp replay(_context, nil, _hash), do: :new

  defp replay(context, key, hash) do
    case FiscalStore.get_document_by_idempotency_key(context, key) do
      nil -> :new
      %{request_hash: ^hash} = document -> {:ok, document}
      _different -> {:error, :idempotency_key_reused}
    end
  end

  defp store_document(context, document, branch_code, request_hash, actor_id, now) do
    series = DocumentSeries.series(document.kind, branch_code || 0)
    sequence = FiscalStore.next_sequence(context, series)
    number = DocumentSeries.format(series, sequence)
    issued_at = JournalChain.microseconds(now)
    id = Ecto.UUID.generate()

    {lines, document} = Map.pop(document, :lines)

    document =
      Map.merge(document, %{
        id: id,
        series: series,
        sequence: sequence,
        number: number,
        issued_at: issued_at,
        request_hash: request_hash,
        created_by_id: actor_id
      })

    content_hash = document_hash(document, lines)

    with {:ok, entry} <-
           append(context, %{
             event_type: "document_issued",
             subject_type: "fiscal_document",
             subject_id: id,
             actor_id: actor_id,
             occurred_at: issued_at,
             payload: %{
               kind: document.kind,
               number: number,
               issue_date: document.issue_date,
               currency: document.currency,
               net_cents: document.net_cents,
               tax_cents: document.tax_cents,
               gross_cents: document.gross_cents,
               corrects_document_id: document.corrects_document_id,
               content_hash: content_hash
             }
             |> put_present(:credit_reason, Map.get(document, :credit_reason))
           }) do
      with {:ok, saved} <-
             FiscalStore.insert_document(
               context,
               Map.merge(document, %{content_hash: content_hash, journal_position: entry.position}),
               lines
             ),
           :ok <- Reporting.enqueue(context, saved, issued_at),
           :ok <- EInvoicing.enqueue(context, saved, issued_at),
           :ok <- TillSigning.enqueue(context, saved, issued_at) do
        {:ok, saved}
      end
    end
  end

  @document_hash_fields ~w(kind series sequence number issue_date issued_at currency
                           prices_include_tax country_code language seller buyer payment_method
                           net_cents tax_cents gross_cents tax_breakdown corrects_document_id
                           source_type source_id)a
  @line_hash_fields ~w(position description quantity unit_price_cents discount_cents amount_cents
                       tax_category rate_bp exemption_reason net_cents tax_cents gross_cents
                       corrects_position source_type source_id)a

  # ADR-265: a credit note's reason is part of what was printed. It is
  # hashed only when present, so documents issued before keep their hash.
  @optional_hash_fields ~w(credit_reason)a

  @doc "SHA-256 of a document's canonical content (what was printed)."
  def document_hash(document, lines) do
    optional =
      document
      |> Map.take(@optional_hash_fields)
      |> Map.reject(fn {_field, value} -> is_nil(value) end)

    %{
      document:
        document
        |> Map.take(@document_hash_fields)
        |> Map.merge(optional)
        |> Map.update(:issued_at, nil, &iso/1),
      lines: Enum.map(lines, &Map.take(&1, @line_hash_fields))
    }
    |> hash_term()
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp iso(%DateTime{} = at), do: at |> JournalChain.microseconds() |> DateTime.to_iso8601()
  defp iso(value), do: value

  defp hash_term(term),
    do: :crypto.hash(:sha256, CanonicalJson.encode!(term)) |> Base.encode16(case: :lower)

  def get_document(context, id), do: FiscalStore.get_document(context, id, [])

  @doc "The document issued under `idempotency_key`, or nil (ADR-262)."
  def document_by_key(context, key) when is_binary(key),
    do: FiscalStore.get_document_by_idempotency_key(context, key)

  @doc "Documents, newest first; filters: kind, from, to, number, limit, offset."
  def list_documents(context, filters \\ %{}), do: FiscalStore.list_documents(context, filters)

  @doc "Credit notes issued against a document."
  def credit_notes(context, document_id),
    do:
      FiscalStore.list_documents(context, %{corrects_document_id: document_id, limit: 200}).documents

  # ── Journal ─────────────────────────────────────────────────────────────

  @doc false
  # Appends one signed entry; must run inside `FiscalStore.transaction/2`.
  def append(context, attrs) do
    head = FiscalStore.lock_journal_head(context)

    with {:ok, entry} <-
           JournalChain.next(head, Map.put(attrs, :organization_id, context.organization_id)),
         {:ok, %{signature: signature, key_id: key_id}} <- signer().sign(entry.hash) do
      FiscalStore.insert_journal_entry(
        context,
        Map.merge(entry, %{signature: signature, signature_key_id: key_id})
      )
    end
  end

  @doc """
  Recomputes the whole chain and every signature (ADR-242) and journals the
  check. `{:ok, %{valid, entries, head | broken_at, reason}}`.
  """
  def verify_journal(context, actor_id, %DateTime{} = now) do
    result = check_chain(context)

    FiscalStore.transaction(context, fn ->
      with {:ok, _entry} <-
             append(context, %{
               event_type: "journal_verified",
               subject_type: "fiscal_journal",
               actor_id: actor_id,
               occurred_at: now,
               payload: Map.new(result, fn {key, value} -> {key, value} end)
             }) do
        {:ok, result}
      end
    end)
  end

  defp check_chain(context) do
    signer = signer()

    verify_signature = fn entry ->
      signer.verify(entry.hash, entry.signature, entry.signature_key_id)
    end

    Stream.unfold(0, fn after_position ->
      case FiscalStore.list_journal_entries(context, %{
             after_position: after_position,
             limit: @verify_batch
           }) do
        [] -> nil
        batch -> {batch, List.last(batch).position}
      end
    end)
    |> Enum.concat()
    |> JournalChain.verify(verify_signature)
  end

  # ── Closings ────────────────────────────────────────────────────────────

  @doc """
  Closes every period that has ended by `today` (the gym-local date),
  oldest first. `{:ok, closings}`; a gym without identity or documents
  closes nothing.
  """
  def close_due_periods(context, %Date{} = today, %DateTime{} = now) do
    first = FiscalStore.first_issue_date(context)
    latest = FiscalStore.latest_closings(context)
    last_closed = Map.new(latest, fn {kind, closing} -> {kind, closing.period_end} end)

    PeriodClosing.due(today, first, last_closed)
    |> Enum.reduce_while({:ok, []}, fn {kind, from, to}, {:ok, acc} ->
      case close(context, kind, from, to, now) do
        {:ok, closing} -> {:cont, {:ok, [closing | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, closings} -> {:ok, Enum.reverse(closings)}
      error -> error
    end
  end

  defp close(context, kind, from, to, now) do
    FiscalStore.transaction(context, fn ->
      previous = Map.get(FiscalStore.latest_closings(context), kind)
      documents = FiscalStore.documents_between(context, from, to)
      totals = PeriodClosing.totals(documents, (previous && previous.totals) || %{})

      with {:ok, entry} <-
             append(context, %{
               event_type: "period_closed",
               subject_type: "fiscal_period",
               occurred_at: now,
               payload: %{period_kind: kind, period_start: from, period_end: to, totals: totals}
             }) do
        FiscalStore.insert_closing(context, %{
          period_kind: kind,
          period_start: from,
          period_end: to,
          totals: totals,
          journal_position: entry.position,
          closed_at: JournalChain.microseconds(now)
        })
      end
    end)
  end

  def list_closings(context, filters \\ %{}), do: FiscalStore.list_closings(context, filters)

  # ── Audit archive ───────────────────────────────────────────────────────

  @doc """
  The audit archive of `from`..`to` (ADR-242): a ZIP with documents, lines,
  closings and the journal as JSON Lines, a manifest with each file's
  SHA-256, its signature and the public keys. The export is journaled.
  `{:ok, %{filename, content}}`.
  """
  def archive(context, %Date{} = from, %Date{} = to, actor_id, %DateTime{} = now) do
    documents = FiscalStore.documents_between(context, from, to)

    lines =
      Enum.flat_map(documents, fn document ->
        context |> FiscalStore.get_document(document.id, []) |> Map.fetch!(:lines)
      end)

    closings = FiscalStore.list_closings(context, %{from: from, to: to, limit: 2_000})
    journal = all_journal_entries(context)

    files = [
      {"documents.jsonl", jsonl(documents, &Map.delete(&1, :lines))},
      {"document_lines.jsonl", jsonl(lines, & &1)},
      {"closings.jsonl", jsonl(closings, & &1)},
      {"journal.jsonl", jsonl(journal, & &1)},
      {"public_keys.json", Jason.encode!(signer().public_keys(), pretty: true)}
    ]

    manifest = %{
      format: "palee-fiscal-archive",
      version: 1,
      organization_id: context.organization_id,
      from: from,
      to: to,
      generated_at: JournalChain.microseconds(now),
      journal_head:
        journal |> List.last() |> then(&(&1 && %{position: &1.position, hash: &1.hash})),
      files:
        Enum.map(files, fn {name, content} ->
          %{
            name: name,
            bytes: byte_size(content),
            sha256: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
          }
        end)
    }

    manifest_json = CanonicalJson.encode!(manifest)

    FiscalStore.transaction(context, fn ->
      with {:ok, signature} <- signer().sign(manifest_json),
           {:ok, _entry} <-
             append(context, %{
               event_type: "archive_exported",
               subject_type: "fiscal_archive",
               actor_id: actor_id,
               occurred_at: now,
               payload: %{
                 from: from,
                 to: to,
                 manifest_sha256:
                   :crypto.hash(:sha256, manifest_json) |> Base.encode16(case: :lower)
               }
             }),
           entries =
             Enum.map(
               files ++
                 [
                   {"manifest.json", manifest_json},
                   {"manifest.sig", Jason.encode!(signature)}
                 ],
               fn {name, content} -> {String.to_charlist(name), content} end
             ),
           {:ok, {_name, zip}} <- :zip.create(~c"archive.zip", entries, [:memory]) do
        {:ok,
         %{
           filename: "palee-fiscal-#{Date.to_iso8601(from)}-#{Date.to_iso8601(to)}.zip",
           content: zip
         }}
      else
        {:error, reason} when is_atom(reason) -> {:error, reason}
        {:error, _reason} -> {:error, :archive_failed}
      end
    end)
  end

  defp all_journal_entries(context) do
    Stream.unfold(0, fn after_position ->
      case FiscalStore.list_journal_entries(context, %{
             after_position: after_position,
             limit: @verify_batch
           }) do
        [] -> nil
        batch -> {batch, List.last(batch).position}
      end
    end)
    |> Enum.concat()
  end

  defp jsonl(rows, view) do
    rows
    |> Enum.map(fn row -> row |> view.() |> Jason.encode!() end)
    |> Enum.join("\n")
    |> case do
      "" -> ""
      body -> body <> "\n"
    end
  end

  # ── Tenant data (ADR-117) ───────────────────────────────────────────────

  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  @doc "Fiscal rows are insert-only; the store lifts that for the purge alone."
  def purge_tenant_data(%{organization_id: organization_id} = context)
      when is_binary(organization_id),
      do: FiscalStore.purge(context)

  def purge_tenant_data(_context), do: {:error, :organization_context_required}
end
