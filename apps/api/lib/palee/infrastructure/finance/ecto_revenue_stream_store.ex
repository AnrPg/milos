defmodule Palee.Infrastructure.Finance.EctoRevenueStreamStore do
  @moduledoc """
  Ecto adapter of `Finance.Ports.RevenueStreamStore` (ADR-190). Writes the
  Finance rows of a revenue stream (the shop) through the `stream_changeset`s
  of the existing Finance schemas, so they sit in the same tables, numbering
  and exports as membership money, tagged with `revenue_stream` and
  `source_type` / `source_id`.

  Every write runs in one transaction under row locks (`FOR UPDATE`) on the
  invoice or payment it changes; payments are idempotent per source and
  reversals per idempotency key.
  """

  @behaviour Palee.Finance.Ports.RevenueStreamStore

  import Ecto.Query

  alias Palee.Finance.{
    FinanceAccountingStore,
    FinanceInvoice,
    FinanceInvoiceLine,
    FinancePaymentReversal,
    MembershipPayment
  }

  alias Palee.Finance.Domain.{InvoiceNumber, RefundReceipt}
  alias Palee.Infrastructure.Tenancy.{GymClock, RepoContext}
  alias Palee.Repo

  @impl true
  def record_invoice(_context, attrs) do
    attrs = string_keys(attrs)
    lines = Map.get(attrs, "lines", [])

    Repo.transaction(fn ->
      subtotal = Enum.sum(Enum.map(lines, &(&1["quantity"] * &1["unit_amount_cents"])))
      discount = Enum.sum(Enum.map(lines, &(&1["discount_cents"] || 0)))

      invoice =
        %FinanceInvoice{}
        |> FinanceInvoice.stream_changeset(
          attrs
          |> Map.drop(["lines"])
          |> Map.put("invoice_number", invoice_number(attrs["revenue_stream"]))
          |> Map.put_new("status", "issued")
          |> Map.put("subtotal_cents", subtotal)
          |> Map.put("discount_cents", discount)
          |> Map.put("total_cents", subtotal - discount)
        )
        |> Repo.insert()
        |> ok_or_rollback()

      saved_lines =
        Enum.map(lines, fn line ->
          %FinanceInvoiceLine{}
          |> FinanceInvoiceLine.stream_changeset(
            line
            |> Map.put("finance_invoice_id", invoice.id)
            |> Map.put_new("revenue_stream", invoice.revenue_stream)
          )
          |> Repo.insert()
          |> ok_or_rollback()
        end)

      invoice |> invoice_map() |> Map.put(:lines, Enum.map(saved_lines, &line_map/1))
    end)
  end

  @impl true
  def record_payment(_context, attrs) do
    attrs = string_keys(attrs)

    Repo.transaction(fn ->
      invoice = attrs["finance_invoice_id"] && locked_invoice(attrs["finance_invoice_id"])

      cond do
        attrs["finance_invoice_id"] && is_nil(invoice) ->
          Repo.rollback(:invoice_not_found)

        invoice && invoice.status == "void" ->
          Repo.rollback(:invoice_void)

        existing = existing_payment(attrs["source_type"], attrs["source_id"]) ->
          payment_map(existing)

        true ->
          payment =
            %MembershipPayment{}
            |> MembershipPayment.stream_changeset(attrs)
            |> Repo.insert()
            |> case do
              {:ok, payment} ->
                payment

              {:error, changeset} ->
                # A concurrent capture won the unique index: return its row.
                existing_payment(attrs["source_type"], attrs["source_id"]) ||
                  Repo.rollback(changeset)
            end

          if invoice, do: refresh_status(invoice)
          payment_map(payment)
      end
    end)
  end

  @impl true
  def reverse_payment(_context, attrs) do
    attrs = string_keys(attrs)

    Repo.transaction(fn ->
      with %MembershipPayment{} = payment <- locked_payment(attrs["membership_payment_id"]),
           amount when is_integer(amount) and amount > 0 <- attrs["amount_cents"],
           :ok <- refundable(payment, amount, attrs["idempotency_key"]) do
        reversal =
          case existing_reversal(attrs["idempotency_key"]) do
            %FinancePaymentReversal{} = reversal ->
              reversal

            nil ->
              %FinancePaymentReversal{}
              |> FinancePaymentReversal.stream_changeset(%{
                "membership_id" => payment.membership_id,
                "user_id" => attrs["user_id"],
                "membership_payment_id" => payment.id,
                "finance_invoice_id" => payment.finance_invoice_id,
                "reversal_type" => "refund",
                "amount_cents" => amount,
                "currency" => payment.currency,
                "occurred_on" => GymClock.today(),
                "occurred_at" => DateTime.utc_now(),
                "reason" => attrs["reason"],
                "created_by_id" => attrs["created_by_id"],
                "idempotency_key" => attrs["idempotency_key"],
                "params" => attrs["params"] || %{}
              })
              |> Repo.insert()
              |> ok_or_rollback()
              |> issue_receipt(attrs["receipt_party"])
          end

        if payment.finance_invoice_id do
          payment.finance_invoice_id |> locked_invoice() |> refresh_status()
        end

        reversal_map(reversal)
      else
        nil -> Repo.rollback(:payment_not_found)
        {:error, reason} -> Repo.rollback(reason)
        _invalid -> Repo.rollback(:invalid_refund_amount)
      end
    end)
  end

  # ADR-126: a member's refund gets its refund receipt in the same
  # transaction. A walk-in refund has no party to name (TD-190).
  defp issue_receipt(%FinancePaymentReversal{user_id: nil} = reversal, _party), do: reversal

  defp issue_receipt(%FinancePaymentReversal{} = reversal, party) do
    if RefundReceipt.required?(reversal.reversal_type) do
      case FinanceAccountingStore.issue_refund_receipt(reversal.id, party) do
        {:ok, _receipt} -> reversal
        {:error, reason} -> Repo.rollback(reason)
      end
    else
      reversal
    end
  end

  @impl true
  def void_invoice(_context, invoice_id, attrs) do
    attrs = string_keys(attrs)

    Repo.transaction(fn ->
      case locked_invoice(invoice_id) do
        nil ->
          Repo.rollback(:invoice_not_found)

        %FinanceInvoice{status: "void"} = invoice ->
          invoice_map(invoice)

        %FinanceInvoice{} = invoice ->
          if paid_cents(invoice.id) > 0 do
            Repo.rollback(:invoice_has_payments)
          else
            invoice
            |> FinanceInvoice.stream_changeset(%{
              "status" => "void",
              "voided_at" => DateTime.utc_now(),
              "params" => Map.put(invoice.params || %{}, "void_reason", attrs["reason"])
            })
            |> Repo.update()
            |> ok_or_rollback()
            |> invoice_map()
          end
      end
    end)
  end

  @impl true
  def set_fiscal_receipt_ref(_context, invoice_id, ref) do
    case FinanceInvoice |> tenant_scope() |> Repo.get(invoice_id) do
      nil ->
        {:error, :invoice_not_found}

      invoice ->
        invoice
        |> FinanceInvoice.stream_changeset(%{"fiscal_receipt_ref" => ref})
        |> Repo.update()
        |> case do
          {:ok, invoice} -> {:ok, invoice_map(invoice)}
          error -> error
        end
    end
  end

  @impl true
  def stream_rows(_context, %Date{} = from, %Date{} = to, filters) do
    users = Map.get(filters, :user_ids)

    payments =
      from(payment in tenant_scope(MembershipPayment),
        where: is_nil(payment.deleted_at) and payment.payment_status in ["paid", "waived"],
        where:
          fragment("COALESCE(?, CAST(? AS date))", payment.paid_on, payment.inserted_at) >= ^from,
        where:
          fragment("COALESCE(?, CAST(? AS date))", payment.paid_on, payment.inserted_at) <= ^to,
        left_join: invoice in FinanceInvoice,
        on: invoice.id == payment.finance_invoice_id,
        group_by: [payment.revenue_stream, payment.currency],
        select: %{
          revenue_stream: payment.revenue_stream,
          currency: payment.currency,
          cents: sum(payment.amount_cents)
        }
      )
      |> maybe_users(users, :payment)
      |> Repo.all()
      |> Enum.map(&integer_cents/1)

    reversals =
      from(reversal in tenant_scope(FinancePaymentReversal),
        where: is_nil(reversal.deleted_at),
        where: reversal.occurred_on >= ^from and reversal.occurred_on <= ^to,
        group_by: [reversal.revenue_stream, reversal.currency],
        select: %{
          revenue_stream: reversal.revenue_stream,
          currency: reversal.currency,
          cents: sum(reversal.amount_cents)
        }
      )
      |> maybe_users(users, :reversal)
      |> Repo.all()
      |> Enum.map(&integer_cents/1)

    %{payments: payments, reversals: reversals}
  end

  defp maybe_users(query, nil, _kind), do: query

  defp maybe_users(query, user_ids, :payment) when is_list(user_ids),
    do: where(query, [_payment, invoice], invoice.user_id in ^user_ids)

  defp maybe_users(query, user_ids, :reversal) when is_list(user_ids),
    do: where(query, [reversal], reversal.user_id in ^user_ids)

  @impl true
  def lineage(_context, source_type, source_id) do
    lines =
      FinanceInvoiceLine
      |> tenant_scope()
      |> where([line], line.source_type == ^source_type and line.source_id == ^source_id)
      |> Repo.all()

    payments =
      MembershipPayment
      |> tenant_scope()
      |> where([payment], payment.source_type == ^source_type and payment.source_id == ^source_id)
      |> where([payment], is_nil(payment.deleted_at))
      |> Repo.all()

    reversals =
      FinancePaymentReversal
      |> tenant_scope()
      |> where(
        [reversal],
        reversal.source_type == ^source_type and reversal.source_id == ^source_id
      )
      |> where([reversal], is_nil(reversal.deleted_at))
      |> Repo.all()

    %{
      invoice_lines: Enum.map(lines, &line_map/1),
      payments: Enum.map(payments, &payment_map/1),
      reversals: Enum.map(reversals, &reversal_map/1)
    }
  end

  @impl true
  def list_for_user(_context, stream, user_id) do
    invoices =
      FinanceInvoice
      |> tenant_scope()
      |> where([invoice], invoice.user_id == ^user_id and invoice.revenue_stream == ^stream)
      |> where([invoice], is_nil(invoice.deleted_at))
      |> order_by([invoice], desc: invoice.inserted_at)
      |> limit(500)
      |> Repo.all()

    ids = Enum.map(invoices, & &1.id)

    payments =
      MembershipPayment
      |> tenant_scope()
      |> where([payment], payment.finance_invoice_id in ^ids and is_nil(payment.deleted_at))
      |> Repo.all()
      |> Enum.group_by(& &1.finance_invoice_id)

    reversals =
      FinancePaymentReversal
      |> tenant_scope()
      |> where([reversal], reversal.finance_invoice_id in ^ids and is_nil(reversal.deleted_at))
      |> Repo.all()
      |> Enum.group_by(& &1.finance_invoice_id)

    Enum.map(invoices, fn invoice ->
      invoice
      |> invoice_map()
      |> Map.put(:payments, Enum.map(Map.get(payments, invoice.id, []), &payment_map/1))
      |> Map.put(:reversals, Enum.map(Map.get(reversals, invoice.id, []), &reversal_map/1))
    end)
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp refundable(payment, amount, key) do
    cond do
      not is_binary(key) or byte_size(key) < 8 -> {:error, :idempotency_key_required}
      existing_reversal(key) -> :ok
      payment.payment_status not in ["paid"] -> {:error, :payment_not_refundable}
      reversed_cents(payment.id) + amount > payment.amount_cents -> {:error, :refund_exceeds_paid}
      true -> :ok
    end
  end

  defp refresh_status(%FinanceInvoice{status: "void"}), do: :ok

  defp refresh_status(%FinanceInvoice{} = invoice) do
    paid = paid_cents(invoice.id)
    reversed = invoice_reversed_cents(invoice.id)

    status =
      cond do
        paid > 0 and reversed >= paid -> "refunded"
        reversed > 0 -> "partially_refunded"
        paid >= invoice.total_cents -> "paid"
        paid > 0 -> "partially_paid"
        true -> invoice.status
      end

    if status != invoice.status do
      invoice
      |> FinanceInvoice.stream_changeset(%{"status" => status})
      |> Repo.update()
      |> ok_or_rollback()
    end

    :ok
  end

  defp refresh_status(nil), do: :ok

  defp invoice_number(stream) do
    {:ok, %{rows: [[sequence]]}} = Repo.query("SELECT nextval('finance_invoice_number_seq')")
    InvoiceNumber.format(sequence, DateTime.utc_now(), stream || "manual")
  end

  defp locked_invoice(id) do
    FinanceInvoice
    |> tenant_scope()
    |> where([invoice], invoice.id == ^id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp locked_payment(nil), do: nil

  defp locked_payment(id) do
    MembershipPayment
    |> tenant_scope()
    |> where([payment], payment.id == ^id and is_nil(payment.deleted_at))
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp existing_payment(source_type, source_id)
       when is_binary(source_type) and is_binary(source_id) do
    MembershipPayment
    |> tenant_scope()
    |> where([payment], payment.source_type == ^source_type and payment.source_id == ^source_id)
    |> where([payment], is_nil(payment.deleted_at))
    |> limit(1)
    |> Repo.one()
  end

  defp existing_payment(_source_type, _source_id), do: nil

  defp existing_reversal(key) when is_binary(key) do
    FinancePaymentReversal |> tenant_scope() |> Repo.get_by(idempotency_key: key)
  end

  defp existing_reversal(_key), do: nil

  defp paid_cents(invoice_id) do
    MembershipPayment
    |> tenant_scope()
    |> where([payment], payment.finance_invoice_id == ^invoice_id)
    |> where([payment], is_nil(payment.deleted_at) and payment.payment_status == "paid")
    |> Repo.aggregate(:sum, :amount_cents)
    |> Kernel.||(0)
  end

  defp reversed_cents(payment_id) do
    FinancePaymentReversal
    |> tenant_scope()
    |> where(
      [reversal],
      reversal.membership_payment_id == ^payment_id and is_nil(reversal.deleted_at)
    )
    |> Repo.aggregate(:sum, :amount_cents)
    |> Kernel.||(0)
  end

  defp invoice_reversed_cents(invoice_id) do
    FinancePaymentReversal
    |> tenant_scope()
    |> where(
      [reversal],
      reversal.finance_invoice_id == ^invoice_id and is_nil(reversal.deleted_at)
    )
    |> Repo.aggregate(:sum, :amount_cents)
    |> Kernel.||(0)
  end

  defp tenant_scope(queryable) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) and organization_id != "" ->
        from(row in queryable, where: field(row, :organization_id) == ^organization_id)

      _missing ->
        from(row in queryable, where: false)
    end
  end

  defp ok_or_rollback({:ok, value}), do: value
  defp ok_or_rollback({:error, reason}), do: Repo.rollback(reason)

  defp integer_cents(%{cents: cents} = row), do: %{row | cents: to_integer(cents)}

  defp to_integer(nil), do: 0
  defp to_integer(%Decimal{} = value), do: Decimal.to_integer(value)
  defp to_integer(value) when is_integer(value), do: value

  defp string_keys(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp invoice_map(%FinanceInvoice{} = invoice) do
    Map.take(invoice, [
      :id,
      :membership_id,
      :user_id,
      :invoice_number,
      :status,
      :issue_date,
      :subtotal_cents,
      :discount_cents,
      :total_cents,
      :currency,
      :revenue_stream,
      :fiscal_receipt_ref,
      :params,
      :voided_at,
      :inserted_at
    ])
  end

  defp line_map(%FinanceInvoiceLine{} = line) do
    Map.take(line, [
      :id,
      :finance_invoice_id,
      :line_type,
      :description,
      :quantity,
      :unit_amount_cents,
      :discount_cents,
      :total_cents,
      :revenue_stream,
      :source_type,
      :source_id,
      :params
    ])
  end

  defp payment_map(%MembershipPayment{} = payment) do
    Map.take(payment, [
      :id,
      :membership_id,
      :finance_invoice_id,
      :amount_cents,
      :currency,
      :paid_on,
      :payment_method,
      :payment_status,
      :revenue_stream,
      :source_type,
      :source_id,
      :params,
      :inserted_at
    ])
  end

  defp reversal_map(%FinancePaymentReversal{} = reversal) do
    Map.take(reversal, [
      :id,
      :membership_payment_id,
      :finance_invoice_id,
      :reversal_type,
      :amount_cents,
      :currency,
      :occurred_on,
      :occurred_at,
      :reason,
      :idempotency_key,
      :revenue_stream,
      :source_type,
      :source_id,
      :inserted_at
    ])
  end
end
