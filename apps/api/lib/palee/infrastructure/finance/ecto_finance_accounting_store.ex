defmodule Palee.Infrastructure.Finance.EctoFinanceAccountingStore do
  @moduledoc """
  Ecto adapter for ADR-126 refund receipts, reconciliation records and
  accounting-export runs. Every query is pinned to the session's
  `app.organization_id` (and to forced RLS underneath); without a tenant
  session reads return nothing and writes fail closed.
  """

  @behaviour Palee.Finance.Ports.FinanceAccountingStore

  import Ecto.Query

  alias Palee.Finance.{
    FinanceAccountingExport,
    FinanceCreditLedgerEntry,
    FinanceDocumentCounter,
    FinanceInvoice,
    FinancePaymentReversal,
    FinanceReconciliationRecord,
    FinanceRefundReceipt,
    Membership,
    MembershipPayment
  }

  alias Palee.Finance.Domain.{
    DocumentNumber,
    ReconciliationMatching,
    RefundReceipt
  }

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo

  @default_limit 100
  @max_limit 500

  # --- Refund receipts ------------------------------------------------------

  @impl true
  def issue_refund_receipt(reversal_id, party) do
    with {:ok, organization_id} <- organization_id() do
      Repo.transaction(fn ->
        case Repo.get_by(tenant_scope(FinanceRefundReceipt),
               finance_payment_reversal_id: reversal_id
             ) do
          %FinanceRefundReceipt{} = receipt ->
            normalize_receipt(receipt)

          nil ->
            reversal_id
            |> load_reversal()
            |> issue_for_reversal(organization_id, party)
        end
      end)
    end
  end

  defp issue_for_reversal(nil, _organization_id, _party), do: Repo.rollback(:not_found)

  defp issue_for_reversal(%FinancePaymentReversal{} = reversal, organization_id, party) do
    if RefundReceipt.required?(reversal.reversal_type) do
      payment = Repo.get!(tenant_scope(MembershipPayment), reversal.membership_payment_id)

      invoice =
        reversal.finance_invoice_id &&
          Repo.get(tenant_scope(FinanceInvoice), reversal.finance_invoice_id)

      sequence = next_sequence!(organization_id, "refund_receipt")
      receipt_number = DocumentNumber.format("refund_receipt", sequence)
      issued_at = DateTime.utc_now()

      snapshot =
        RefundReceipt.build_snapshot(%{
          organization_id: organization_id,
          receipt_number: receipt_number,
          sequence: sequence,
          issued_at: issued_at,
          party: party,
          reversal: reversal,
          payment: payment,
          invoice: invoice,
          payment_reversed_total_cents: payment_reversed_cents(payment.id)
        })

      %{
        finance_payment_reversal_id: reversal.id,
        membership_payment_id: payment.id,
        finance_invoice_id: invoice && invoice.id,
        membership_id: reversal.membership_id,
        user_id: reversal.user_id,
        sequence: sequence,
        receipt_number: receipt_number,
        reversal_type: reversal.reversal_type,
        amount_cents: reversal.amount_cents,
        currency: reversal.currency,
        reason: snapshot["reversal"]["reason"],
        issued_by_id: reversal.created_by_id,
        reversal_occurred_at: reversal.occurred_at,
        issued_at: issued_at,
        schema_version: RefundReceipt.schema_version(),
        snapshot: snapshot,
        snapshot_sha256: RefundReceipt.sha256(snapshot)
      }
      |> FinanceRefundReceipt.create_changeset()
      |> Repo.insert()
      |> case do
        {:ok, receipt} -> normalize_receipt(receipt)
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end
  end

  # Gapless numbering: make sure the tenant's counter row exists, lock it for
  # the rest of the transaction, then advance it. Concurrent issuers queue on
  # the row lock; a rollback restores the previous value.
  defp next_sequence!(organization_id, document_type) do
    now = DateTime.utc_now()

    Repo.insert_all(
      FinanceDocumentCounter,
      [
        %{
          id: Ecto.UUID.generate(),
          organization_id: organization_id,
          document_type: document_type,
          last_value: 0,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:organization_id, :document_type]
    )

    counter =
      FinanceDocumentCounter
      |> tenant_scope()
      |> where([counter], counter.document_type == ^document_type)
      |> lock("FOR UPDATE")
      |> Repo.one!()

    sequence = DocumentNumber.next_sequence(counter.last_value)

    counter
    |> FinanceDocumentCounter.changeset(%{last_value: sequence})
    |> Repo.update!()

    sequence
  end

  @impl true
  def list_refund_receipts(filters) do
    filters = string_keys(filters)

    receipt_query()
    |> maybe_filter(:user_id, filters["user_id"])
    |> maybe_filter_users(filters["user_ids"])
    |> maybe_filter_receipt_search(filters["q"])
    |> maybe_date_range(filters["from"], filters["to"])
    |> order_by([receipt], desc: receipt.sequence)
    |> limit(^limit(filters["limit"]))
    |> Repo.all()
    |> Enum.map(&normalize_receipt/1)
  end

  @impl true
  def get_refund_receipt(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %FinanceRefundReceipt{} = receipt <-
           receipt_query() |> where([receipt], receipt.id == ^id) |> Repo.one() do
      normalize_receipt(receipt)
    else
      _ -> nil
    end
  end

  @impl true
  def get_refund_receipt_for_reversal(reversal_id) do
    with {:ok, reversal_id} <- Ecto.UUID.cast(reversal_id),
         %FinanceRefundReceipt{} = receipt <-
           receipt_query()
           |> where([receipt], receipt.finance_payment_reversal_id == ^reversal_id)
           |> Repo.one() do
      normalize_receipt(receipt)
    else
      _ -> nil
    end
  end

  # Receipts of soft-deleted reversals leave normal views (ADR-084); the rows
  # themselves are never changed.
  defp receipt_query do
    from(receipt in tenant_scope(FinanceRefundReceipt),
      join: reversal in FinancePaymentReversal,
      on: reversal.id == receipt.finance_payment_reversal_id,
      where: is_nil(reversal.deleted_at)
    )
  end

  # ADR-186 §7: a branch filter arrives as the people whose home branch it is.
  defp maybe_filter_users(query, users) when is_list(users),
    do: where(query, [receipt], receipt.user_id in ^users)

  defp maybe_filter_users(query, _none), do: query

  defp maybe_filter(query, _field, value) when value in [nil, ""], do: query

  defp maybe_filter(query, field, value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> where(query, [row], field(row, ^field) == ^uuid)
      :error -> where(query, false)
    end
  end

  defp maybe_filter_receipt_search(query, value) when value in [nil, ""], do: query

  defp maybe_filter_receipt_search(query, value) do
    pattern = "%" <> escape_like(String.trim(value)) <> "%"

    where(
      query,
      [receipt],
      ilike(receipt.receipt_number, ^pattern) or
        ilike(fragment("?->'invoice'->>'invoice_number'", receipt.snapshot), ^pattern) or
        ilike(fragment("?->'member'->>'display_name'", receipt.snapshot), ^pattern)
    )
  end

  defp maybe_date_range(query, from, to) do
    query
    |> then(fn query ->
      case parse_date(from) do
        %Date{} = date ->
          where(query, [receipt], fragment("CAST(? AS date)", receipt.issued_at) >= ^date)

        nil ->
          query
      end
    end)
    |> then(fn query ->
      case parse_date(to) do
        %Date{} = date ->
          where(query, [receipt], fragment("CAST(? AS date)", receipt.issued_at) <= ^date)

        nil ->
          query
      end
    end)
  end

  defp normalize_receipt(%FinanceRefundReceipt{} = receipt) do
    snapshot = receipt.snapshot || %{}

    %{
      id: receipt.id,
      organization_id: receipt.organization_id,
      receipt_number: receipt.receipt_number,
      sequence: receipt.sequence,
      finance_payment_reversal_id: receipt.finance_payment_reversal_id,
      membership_payment_id: receipt.membership_payment_id,
      finance_invoice_id: receipt.finance_invoice_id,
      membership_id: receipt.membership_id,
      user_id: receipt.user_id,
      reversal_type: receipt.reversal_type,
      amount_cents: receipt.amount_cents,
      currency: receipt.currency,
      reason: receipt.reason,
      issued_by_id: receipt.issued_by_id,
      reversal_occurred_at: receipt.reversal_occurred_at,
      issued_at: receipt.issued_at,
      invoice_number: get_in(snapshot, ["invoice", "invoice_number"]),
      member_display_name: get_in(snapshot, ["member", "display_name"]),
      schema_version: receipt.schema_version,
      snapshot: snapshot,
      snapshot_sha256: receipt.snapshot_sha256,
      integrity_verified: RefundReceipt.verify(snapshot, receipt.snapshot_sha256)
    }
  end

  # --- Reconciliation -------------------------------------------------------

  @impl true
  def record_reconciliation_line(line, actor_id) do
    with {:ok, _organization_id} <- organization_id() do
      Repo.transaction(fn ->
        case existing_line(line) do
          %FinanceReconciliationRecord{} = existing ->
            replay(existing, line)

          nil ->
            line
            |> Map.put(:recorded_by_id, actor_id)
            |> FinanceReconciliationRecord.create_changeset()
            |> Repo.insert()
            |> case do
              {:ok, record} ->
                {normalize_record(record), :created}

              {:error, changeset} ->
                # A concurrent insert of the same reference won the race.
                case existing_line(line) do
                  %FinanceReconciliationRecord{} = existing -> replay(existing, line)
                  nil -> Repo.rollback(changeset)
                end
            end
        end
      end)
      |> case do
        {:ok, {record, outcome}} -> {:ok, record, outcome}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp existing_line(line) do
    FinanceReconciliationRecord
    |> tenant_scope()
    |> where([record], record.provider == ^line.provider)
    |> where([record], record.external_reference == ^line.external_reference)
    |> Repo.one()
  end

  defp replay(existing, line) do
    if ReconciliationMatching.replay_conflict?(Map.from_struct(existing), line),
      do: Repo.rollback(:reconciliation_reference_conflict),
      else: {normalize_record(existing), :replayed}
  end

  @impl true
  def list_reconciliation_records(filters) do
    filters = string_keys(filters)

    FinanceReconciliationRecord
    |> tenant_scope()
    |> maybe_filter_status(filters["status"])
    |> maybe_filter_provider(filters["provider"])
    |> order_by([record], desc: record.statement_occurred_on, desc: record.inserted_at)
    |> limit(^limit(filters["limit"]))
    |> Repo.all()
    |> Enum.map(&normalize_record/1)
  end

  @impl true
  def get_reconciliation_record(id) do
    case load_record(id, false) do
      %FinanceReconciliationRecord{} = record -> normalize_record(record)
      nil -> nil
    end
  end

  @impl true
  def reconciliation_candidate_facts(id) do
    case load_record(id, false) do
      nil ->
        {:error, :not_found}

      record ->
        {from, to} = ReconciliationMatching.candidate_window(record.statement_occurred_on)
        kind = ReconciliationMatching.target_kind(record.external_type)
        {:ok, normalize_record(record), candidate_facts(kind, record, from, to)}
    end
  end

  defp candidate_facts(:payment, record, from, to) do
    linked = linked_ids(:membership_payment_id, record.id)

    from(payment in tenant_scope(MembershipPayment),
      join: membership in Membership,
      on: membership.id == payment.membership_id,
      left_join: invoice in FinanceInvoice,
      on: invoice.id == payment.finance_invoice_id,
      where: is_nil(payment.deleted_at),
      where: payment.payment_status in ["paid", "pending"],
      where:
        fragment("COALESCE(?, CAST(? AS date))", payment.paid_on, payment.inserted_at) >= ^from,
      where:
        fragment("COALESCE(?, CAST(? AS date))", payment.paid_on, payment.inserted_at) <= ^to,
      where: payment.id not in ^linked,
      order_by: [desc: payment.inserted_at],
      limit: 200,
      select: {payment, membership.user_id, invoice.invoice_number}
    )
    |> Repo.all()
    |> Enum.map(fn {payment, user_id, invoice_number} ->
      payment_fact(payment, user_id, invoice_number)
    end)
  end

  defp candidate_facts(:reversal, record, from, to) do
    linked = linked_ids(:finance_payment_reversal_id, record.id)

    from(reversal in tenant_scope(FinancePaymentReversal),
      left_join: invoice in FinanceInvoice,
      on: invoice.id == reversal.finance_invoice_id,
      where: is_nil(reversal.deleted_at),
      where: reversal.occurred_on >= ^from and reversal.occurred_on <= ^to,
      where: reversal.id not in ^linked,
      order_by: [desc: reversal.occurred_at],
      limit: 200,
      select: {reversal, invoice.invoice_number}
    )
    |> Repo.all()
    |> Enum.map(fn {reversal, invoice_number} -> reversal_fact(reversal, invoice_number) end)
  end

  defp linked_ids(field, except_record_id) do
    FinanceReconciliationRecord
    |> tenant_scope()
    |> where([record], record.id != ^except_record_id)
    |> where([record], not is_nil(field(record, ^field)))
    |> select([record], field(record, ^field))
    |> Repo.all()
  end

  @impl true
  def match_reconciliation_record(id, target_kind, target_id, attrs) do
    with {:ok, _organization_id} <- organization_id() do
      Repo.transaction(fn ->
        with %FinanceReconciliationRecord{} = record <- load_record(id, true),
             %{} = fact <- load_fact(target_kind, target_id) do
          evaluation =
            ReconciliationMatching.evaluate(
              %{
                external_type: record.external_type,
                external_status: record.external_status,
                statement_amount_cents: record.statement_amount_cents,
                statement_currency: record.statement_currency,
                statement_occurred_on: record.statement_occurred_on
              },
              fact
            )

          record
          |> FinanceReconciliationRecord.match_changeset(%{
            status: evaluation.status,
            membership_payment_id: if(target_kind == :payment, do: fact.id),
            finance_payment_reversal_id: if(target_kind == :reversal, do: fact.id),
            discrepancies: evaluation.discrepancies,
            discrepancy_notes: notes(attrs),
            matched_at: DateTime.utc_now(),
            matched_by_id: attrs[:actor_id]
          })
          |> Repo.update()
          |> case do
            {:ok, updated} -> normalize_record(updated)
            {:error, changeset} -> Repo.rollback(match_error(changeset))
          end
        else
          nil -> Repo.rollback(:not_found)
        end
      end)
    end
  end

  @impl true
  def unmatch_reconciliation_record(id, attrs) do
    with {:ok, _organization_id} <- organization_id() do
      Repo.transaction(fn ->
        case load_record(id, true) do
          nil ->
            Repo.rollback(:not_found)

          record ->
            record
            |> FinanceReconciliationRecord.match_changeset(%{
              status: "unmatched",
              membership_payment_id: nil,
              finance_payment_reversal_id: nil,
              discrepancies: [],
              discrepancy_notes: notes(attrs),
              matched_at: nil,
              matched_by_id: attrs[:actor_id]
            })
            |> Repo.update()
            |> case do
              {:ok, updated} -> normalize_record(updated)
              {:error, changeset} -> Repo.rollback(changeset)
            end
        end
      end)
    end
  end

  defp match_error(%Ecto.Changeset{errors: errors} = changeset) do
    if Enum.any?(errors, fn {_field, {_message, opts}} -> opts[:constraint] == :unique end),
      do: :reconciliation_target_already_matched,
      else: changeset
  end

  defp notes(attrs) do
    case attrs[:notes] do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> String.slice(trimmed, 0, 1000)
        end

      _ ->
        nil
    end
  end

  defp load_record(id, lock?) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      FinanceReconciliationRecord
      |> tenant_scope()
      |> where([record], record.id == ^id)
      |> then(fn query -> if lock?, do: lock(query, "FOR UPDATE"), else: query end)
      |> Repo.one()
    else
      _ -> nil
    end
  end

  defp load_fact(:payment, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {payment, user_id, invoice_number} <-
           from(payment in tenant_scope(MembershipPayment),
             join: membership in Membership,
             on: membership.id == payment.membership_id,
             left_join: invoice in FinanceInvoice,
             on: invoice.id == payment.finance_invoice_id,
             where: payment.id == ^id and is_nil(payment.deleted_at),
             select: {payment, membership.user_id, invoice.invoice_number}
           )
           |> Repo.one() do
      payment_fact(payment, user_id, invoice_number)
    else
      _ -> nil
    end
  end

  defp load_fact(:reversal, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {reversal, invoice_number} <-
           from(reversal in tenant_scope(FinancePaymentReversal),
             left_join: invoice in FinanceInvoice,
             on: invoice.id == reversal.finance_invoice_id,
             where: reversal.id == ^id and is_nil(reversal.deleted_at),
             select: {reversal, invoice.invoice_number}
           )
           |> Repo.one() do
      reversal_fact(reversal, invoice_number)
    else
      _ -> nil
    end
  end

  defp payment_fact(%MembershipPayment{} = payment, user_id, invoice_number) do
    %{
      id: payment.id,
      kind: :payment,
      amount_cents: payment.amount_cents,
      currency: payment.currency,
      occurred_on: payment.paid_on || DateTime.to_date(payment.inserted_at),
      status: payment.payment_status,
      payment_method: payment.payment_method,
      user_id: user_id,
      invoice_number: invoice_number
    }
  end

  defp reversal_fact(%FinancePaymentReversal{} = reversal, invoice_number) do
    %{
      id: reversal.id,
      kind: :reversal,
      amount_cents: reversal.amount_cents,
      currency: reversal.currency,
      occurred_on: reversal.occurred_on,
      status: reversal.reversal_type,
      payment_method: nil,
      user_id: reversal.user_id,
      invoice_number: invoice_number
    }
  end

  defp maybe_filter_status(query, value) when value in ["unmatched", "matched", "mismatched"],
    do: where(query, [record], record.status == ^value)

  defp maybe_filter_status(query, _value), do: query

  defp maybe_filter_provider(query, value) when is_binary(value) and value != "",
    do: where(query, [record], record.provider == ^String.downcase(String.trim(value)))

  defp maybe_filter_provider(query, _value), do: query

  defp normalize_record(%FinanceReconciliationRecord{} = record) do
    %{
      id: record.id,
      organization_id: record.organization_id,
      provider: record.provider,
      external_reference: record.external_reference,
      external_type: record.external_type,
      external_status: record.external_status,
      statement_amount_cents: record.statement_amount_cents,
      statement_currency: record.statement_currency,
      statement_occurred_on: record.statement_occurred_on,
      statement_description: record.statement_description,
      status: record.status,
      target_type: target_type(record),
      membership_payment_id: record.membership_payment_id,
      finance_payment_reversal_id: record.finance_payment_reversal_id,
      discrepancies: record.discrepancies || [],
      discrepancy_notes: record.discrepancy_notes,
      matched_at: record.matched_at,
      matched_by_id: record.matched_by_id,
      recorded_by_id: record.recorded_by_id,
      inserted_at: record.inserted_at,
      updated_at: record.updated_at
    }
  end

  defp target_type(%{membership_payment_id: id}) when is_binary(id), do: "payment"
  defp target_type(%{finance_payment_reversal_id: id}) when is_binary(id), do: "reversal"
  defp target_type(_record), do: nil

  # --- Accounting exports ---------------------------------------------------

  @impl true
  def create_accounting_export(attrs) do
    with {:ok, _organization_id} <- organization_id() do
      attrs
      |> FinanceAccountingExport.create_changeset()
      |> Repo.insert()
      |> case do
        {:ok, export} -> {:ok, normalize_export(export)}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  @impl true
  def update_accounting_export(id, attrs) do
    case load_export(id) do
      nil ->
        {:error, :not_found}

      export ->
        export
        |> FinanceAccountingExport.progress_changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, normalize_export(updated)}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @impl true
  def get_accounting_export(id) do
    case load_export(id) do
      nil -> nil
      export -> normalize_export(export)
    end
  end

  @impl true
  def list_accounting_exports(filters) do
    FinanceAccountingExport
    |> tenant_scope()
    |> order_by([export], desc: export.inserted_at)
    |> limit(^limit(string_keys(filters)["limit"]))
    |> Repo.all()
    |> Enum.map(&normalize_export/1)
  end

  defp load_export(id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Repo.get(tenant_scope(FinanceAccountingExport), id)
    else
      _ -> nil
    end
  end

  defp normalize_export(%FinanceAccountingExport{} = export) do
    %{
      id: export.id,
      organization_id: export.organization_id,
      requested_by_id: export.requested_by_id,
      range_start: export.range_start,
      range_end: export.range_end,
      status: export.status,
      execution_mode: export.execution_mode,
      schema_version: export.schema_version,
      object_key: export.object_key,
      byte_size: export.byte_size,
      sha256: export.sha256,
      row_counts: export.row_counts || %{},
      files: export.files || [],
      error_reason: export.error_reason,
      started_at: export.started_at,
      completed_at: export.completed_at,
      inserted_at: export.inserted_at,
      updated_at: export.updated_at
    }
  end

  @impl true
  def accounting_export_rows(%Date{} = range_start, %Date{} = range_end) do
    %{
      "payments" => payment_rows(range_start, range_end),
      "allocations" => allocation_rows(range_start, range_end),
      "reversals" => reversal_rows(range_start, range_end),
      "credits" => credit_rows(range_start, range_end),
      "refund_receipts" => receipt_rows(range_start, range_end)
    }
  end

  defp payment_rows(range_start, range_end) do
    reversed = reversed_by_payment()

    from(payment in tenant_scope(MembershipPayment),
      join: membership in Membership,
      on: membership.id == payment.membership_id,
      left_join: invoice in FinanceInvoice,
      on: invoice.id == payment.finance_invoice_id,
      left_join: reversed in subquery(reversed),
      on: reversed.payment_id == payment.id,
      where: is_nil(payment.deleted_at),
      where:
        fragment("COALESCE(?, CAST(? AS date))", payment.paid_on, payment.inserted_at) >=
          ^range_start,
      where:
        fragment("COALESCE(?, CAST(? AS date))", payment.paid_on, payment.inserted_at) <=
          ^range_end,
      order_by: [asc: payment.paid_on, asc: payment.inserted_at, asc: payment.id],
      select: {payment, membership.user_id, invoice.invoice_number, reversed.cents}
    )
    |> Repo.all()
    |> Enum.map(fn {payment, user_id, invoice_number, reversed_cents} ->
      reversed_cents = to_integer(reversed_cents)

      %{
        "payment_id" => payment.id,
        "paid_on" => payment.paid_on || DateTime.to_date(payment.inserted_at),
        "recorded_at" => payment.inserted_at,
        "member_user_id" => user_id,
        "membership_id" => payment.membership_id,
        "invoice_id" => payment.finance_invoice_id,
        "invoice_number" => invoice_number,
        "package_subscription_id" => payment.membership_package_subscription_id,
        "payment_method" => payment.payment_method,
        "payment_status" => payment.payment_status,
        "currency" => payment.currency,
        "amount_cents" => payment.amount_cents,
        "reversed_cents" => reversed_cents,
        "net_amount_cents" => max(payment.amount_cents - reversed_cents, 0)
      }
    end)
  end

  defp allocation_rows(range_start, range_end) do
    reversed = reversed_by_payment()

    payments =
      from(payment in tenant_scope(MembershipPayment),
        join: membership in Membership,
        on: membership.id == payment.membership_id,
        join: invoice in FinanceInvoice,
        on: invoice.id == payment.finance_invoice_id,
        left_join: reversed in subquery(reversed),
        on: reversed.payment_id == payment.id,
        where: is_nil(payment.deleted_at) and payment.payment_status in ["paid", "waived"],
        where:
          fragment("COALESCE(?, CAST(? AS date))", payment.paid_on, payment.inserted_at) >=
            ^range_start,
        where:
          fragment("COALESCE(?, CAST(? AS date))", payment.paid_on, payment.inserted_at) <=
            ^range_end,
        select: {payment, membership.user_id, invoice.invoice_number, reversed.cents}
      )
      |> Repo.all()
      |> Enum.map(fn {payment, user_id, invoice_number, reversed_cents} ->
        reversed_cents = to_integer(reversed_cents)

        %{
          "allocation_id" => payment.id,
          "allocation_type" => "payment",
          "occurred_on" => payment.paid_on || DateTime.to_date(payment.inserted_at),
          "invoice_id" => payment.finance_invoice_id,
          "invoice_number" => invoice_number,
          "source_payment_id" => payment.id,
          "source_credit_entry_id" => nil,
          "member_user_id" => user_id,
          "currency" => payment.currency,
          "amount_cents" => payment.amount_cents,
          "reversed_cents" => reversed_cents,
          "net_amount_cents" => max(payment.amount_cents - reversed_cents, 0)
        }
      end)

    credit_reversals =
      from(entry in tenant_scope(FinanceCreditLedgerEntry),
        where: not is_nil(entry.reversed_credit_ledger_entry_id),
        where: entry.amount_cents > 0 and is_nil(entry.deleted_at),
        group_by: entry.reversed_credit_ledger_entry_id,
        select: %{entry_id: entry.reversed_credit_ledger_entry_id, cents: sum(entry.amount_cents)}
      )

    credits =
      from(entry in tenant_scope(FinanceCreditLedgerEntry),
        join: invoice in FinanceInvoice,
        on: invoice.id == entry.finance_invoice_id,
        left_join: reversed in subquery(credit_reversals),
        on: reversed.entry_id == entry.id,
        where: entry.entry_type == "invoice_offset" and entry.amount_cents < 0,
        where: is_nil(entry.deleted_at),
        where: entry.occurred_on >= ^range_start and entry.occurred_on <= ^range_end,
        select: {entry, invoice.invoice_number, reversed.cents}
      )
      |> Repo.all()
      |> Enum.map(fn {entry, invoice_number, reversed_cents} ->
        amount = -entry.amount_cents
        reversed_cents = to_integer(reversed_cents)

        %{
          "allocation_id" => entry.id,
          "allocation_type" => "credit",
          "occurred_on" => entry.occurred_on,
          "invoice_id" => entry.finance_invoice_id,
          "invoice_number" => invoice_number,
          "source_payment_id" => nil,
          "source_credit_entry_id" => entry.id,
          "member_user_id" => entry.user_id,
          "currency" => entry.currency,
          "amount_cents" => amount,
          "reversed_cents" => reversed_cents,
          "net_amount_cents" => max(amount - reversed_cents, 0)
        }
      end)

    Enum.sort_by(payments ++ credits, &{Date.to_iso8601(&1["occurred_on"]), &1["allocation_id"]})
  end

  defp reversal_rows(range_start, range_end) do
    from(reversal in tenant_scope(FinancePaymentReversal),
      left_join: invoice in FinanceInvoice,
      on: invoice.id == reversal.finance_invoice_id,
      left_join: receipt in FinanceRefundReceipt,
      on: receipt.finance_payment_reversal_id == reversal.id,
      where: is_nil(reversal.deleted_at),
      where: reversal.occurred_on >= ^range_start and reversal.occurred_on <= ^range_end,
      order_by: [asc: reversal.occurred_at, asc: reversal.id],
      select: {reversal, invoice.invoice_number, receipt.receipt_number}
    )
    |> Repo.all()
    |> Enum.map(fn {reversal, invoice_number, receipt_number} ->
      %{
        "reversal_id" => reversal.id,
        "occurred_on" => reversal.occurred_on,
        "occurred_at" => reversal.occurred_at,
        "reversal_type" => reversal.reversal_type,
        "payment_id" => reversal.membership_payment_id,
        "invoice_id" => reversal.finance_invoice_id,
        "invoice_number" => invoice_number,
        "member_user_id" => reversal.user_id,
        "currency" => reversal.currency,
        "amount_cents" => reversal.amount_cents,
        "reason" => reversal.reason,
        "recorded_by_id" => reversal.created_by_id,
        "refund_receipt_number" => receipt_number
      }
    end)
  end

  defp credit_rows(range_start, range_end) do
    from(entry in tenant_scope(FinanceCreditLedgerEntry),
      where: is_nil(entry.deleted_at),
      where: entry.occurred_on >= ^range_start and entry.occurred_on <= ^range_end,
      order_by: [asc: entry.occurred_at, asc: entry.id]
    )
    |> Repo.all()
    |> Enum.map(fn entry ->
      %{
        "entry_id" => entry.id,
        "occurred_on" => entry.occurred_on,
        "occurred_at" => entry.occurred_at,
        "entry_type" => entry.entry_type,
        "source_type" => entry.source_type,
        "member_user_id" => entry.user_id,
        "payment_id" => entry.membership_payment_id,
        "invoice_id" => entry.finance_invoice_id,
        "reversed_entry_id" => entry.reversed_credit_ledger_entry_id,
        "currency" => entry.currency,
        "amount_cents" => entry.amount_cents,
        "description" => entry.description
      }
    end)
  end

  defp receipt_rows(range_start, range_end) do
    receipt_query()
    |> maybe_date_range(Date.to_iso8601(range_start), Date.to_iso8601(range_end))
    |> order_by([receipt], asc: receipt.sequence)
    |> Repo.all()
    |> Enum.map(fn receipt ->
      %{
        "receipt_id" => receipt.id,
        "receipt_number" => receipt.receipt_number,
        "sequence" => receipt.sequence,
        "issued_at" => receipt.issued_at,
        "reversal_id" => receipt.finance_payment_reversal_id,
        "payment_id" => receipt.membership_payment_id,
        "invoice_id" => receipt.finance_invoice_id,
        "invoice_number" => get_in(receipt.snapshot || %{}, ["invoice", "invoice_number"]),
        "member_user_id" => receipt.user_id,
        "reversal_type" => receipt.reversal_type,
        "currency" => receipt.currency,
        "amount_cents" => receipt.amount_cents,
        "reason" => receipt.reason,
        "snapshot_sha256" => receipt.snapshot_sha256
      }
    end)
  end

  defp reversed_by_payment do
    from(reversal in tenant_scope(FinancePaymentReversal),
      where: is_nil(reversal.deleted_at),
      group_by: reversal.membership_payment_id,
      select: %{payment_id: reversal.membership_payment_id, cents: sum(reversal.amount_cents)}
    )
  end

  # --- Shared helpers -------------------------------------------------------

  defp load_reversal(reversal_id) do
    FinancePaymentReversal
    |> tenant_scope()
    |> where([reversal], reversal.id == ^reversal_id)
    |> Repo.one()
  end

  defp payment_reversed_cents(payment_id) do
    FinancePaymentReversal
    |> tenant_scope()
    |> where([reversal], reversal.membership_payment_id == ^payment_id)
    |> where([reversal], is_nil(reversal.deleted_at))
    |> Repo.aggregate(:sum, :amount_cents)
    |> to_integer()
  end

  defp organization_id do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) and organization_id != "" ->
        {:ok, organization_id}

      _ ->
        {:error, :organization_context_required}
    end
  end

  defp tenant_scope(queryable) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) and organization_id != "" ->
        from(row in queryable, where: field(row, :organization_id) == ^organization_id)

      _ ->
        from(row in queryable, where: false)
    end
  end

  defp limit(value) do
    case value do
      value when is_integer(value) and value > 0 ->
        min(value, @max_limit)

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} when integer > 0 -> min(integer, @max_limit)
          _ -> @default_limit
        end

      _ ->
        @default_limit
    end
  end

  defp parse_date(%Date{} = date), do: date

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_value), do: nil

  defp escape_like(value), do: String.replace(value, ~r/([\\%_])/, "\\\\\\1")

  defp string_keys(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp string_keys(_value), do: %{}

  defp to_integer(nil), do: 0
  defp to_integer(%Decimal{} = value), do: Decimal.to_integer(value)
  defp to_integer(value) when is_integer(value), do: value
end
