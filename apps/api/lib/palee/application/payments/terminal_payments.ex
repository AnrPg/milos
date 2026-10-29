defmodule Palee.Application.Payments.TerminalPayments do
  @moduledoc """
  ADR-249 use cases: staff take a card at the desk on their phone through
  the provider's terminal app (Tap to Pay). Staff pick what the money is
  for; the server works out the amount limits and currency, opens the
  payment and gives the phone the request for the terminal app; the phone
  posts back what the app returned, and the provider confirms it before
  anything is recorded.

  Purposes: an open invoice of the member (up to its balance), a πακέτο
  συνδρομής sold at the desk, a shop order waiting for payment (its total;
  may be a walk-in's) and a free sale (a description, for a member or,
  ADR-264, a walk-in).
  """

  alias Palee.Application.Fiscal.{FiscalDocumentRendering, FiscalReporting, ReceiptLinks}
  alias Palee.Application.{GoLive, UpdateFinanceMember}
  alias Palee.{Finance, Fiscal, Identity, Organizations}
  alias Palee.Payments.Terminal
  alias Palee.Shop

  @open_invoice_statuses ~w(issued partially_paid overdue)
  @charge_categories ~w(product personal_training event other)

  def charge_categories, do: @charge_categories

  @doc "Whether the business can take Tap to Pay now and, when not, why (ADR-272)."
  def availability(context), do: Terminal.availability(context)

  @doc """
  Opens a terminal payment. `params`: `purpose` (finance_invoice,
  membership_package, shop_order, free_sale), `purpose_id` (not for a free
  sale), `user_id` (the member; none for a walk-in's shop
  order or free sale),
  `amount_cents`, `description` and `charge_category` (free sale),
  `idempotency_key`.
  """
  def start(context, params) do
    user_id = params[:user_id]

    with :ok <- purpose_named(params),
         {:ok, purpose} <- resolve(context, params[:purpose], params),
         :ok <- GoLive.check_payment(context, purpose.user_id || user_id),
         {:ok, payment} <-
           Terminal.start(
        context,
        %{
          purpose_type: params[:purpose],
          purpose_id: purpose.purpose_id,
          user_id: purpose.user_id,
          amount_cents: params[:amount_cents],
          currency: purpose.currency,
          description: purpose.description,
          metadata: Map.merge(purpose[:metadata] || %{}, started_on(params)),
          idempotency_key: params[:idempotency_key],
          created_by_id: Map.get(context, :user_id)
        },
        now()
      ) do
      {:ok, decorate(context, payment)}
    end
  end

  # ADR-272: where the payment started, for its tip (a phone by default:
  # Tap to Pay starts on the staff member's phone).
  defp started_on(%{started_on: "desk"}), do: %{"started_on" => "desk"}
  defp started_on(_params), do: %{"started_on" => "phone"}

  # Every purpose but a free sale names its row.
  defp purpose_named(%{purpose: "free_sale"}), do: :ok

  defp purpose_named(params) do
    if is_binary(params[:purpose_id]), do: :ok, else: {:error, :invalid_payment_purpose}
  end

  defp resolve(context, "finance_invoice", params) do
    with {:ok, user_id} <- member(context, params[:user_id]),
         {:ok, invoice} <- open_invoice(context, user_id, params[:purpose_id]),
         :ok <- at_most(params[:amount_cents], invoice.balance_due_cents) do
      {:ok,
       %{
         purpose_id: invoice.id,
         user_id: user_id,
         currency: invoice.currency,
         description: invoice_description(invoice)
       }}
    end
  end

  defp resolve(context, "membership_package", params) do
    with {:ok, user_id} <- member(context, params[:user_id]),
         {:ok, package} <- package_for_desk(context, params[:purpose_id]) do
      {:ok,
       %{
         purpose_id: package.id,
         user_id: user_id,
         currency: package_currency(context, package),
         description: package.name
       }}
    end
  end

  defp resolve(context, "shop_order", params) do
    with %{} = order <- Shop.get_order(context, params[:purpose_id]) || {:error, :not_found},
         true <- order.payment_status == :pending_payment || {:error, :order_not_payable},
         true <- params[:amount_cents] == order.total_cents || {:error, :invalid_payment_amount},
         true <-
           (is_nil(params[:user_id]) or params[:user_id] == order.user_id) ||
             {:error, :not_found} do
      {:ok,
       %{
         purpose_id: order.id,
         user_id: order.user_id,
         currency: order.currency,
         description: "#" <> to_string(order.number)
       }}
    end
  end

  defp resolve(context, "free_sale", params) do
    description = params[:description]
    category = params[:charge_category]

    cond do
      not (is_binary(description) and String.trim(description) != "") ->
        {:error, :payment_purpose_required}

      not (is_nil(category) or category in @charge_categories) ->
        {:error, :invalid_payment_purpose}

      true ->
        with {:ok, user_id} <- free_sale_payer(context, params[:user_id]) do
          {:ok,
           %{
             # A free sale is for the member it is charged to; a walk-in's
             # (ADR-264) is its own sale.
             purpose_id: user_id || Ecto.UUID.generate(),
             user_id: user_id,
             currency: business_currency(context),
             description: String.trim(description),
             metadata: free_sale_metadata(user_id, category)
           }}
        end
    end
  end

  defp resolve(_context, _purpose, _params), do: {:error, :invalid_payment_purpose}

  # ADR-264: a walk-in (no member) may pay a free sale too.
  defp free_sale_payer(_context, nil), do: {:ok, nil}
  defp free_sale_payer(context, user_id), do: member(context, user_id)

  defp free_sale_metadata(user_id, category) do
    %{}
    |> then(&if(category, do: Map.put(&1, "charge_category", category), else: &1))
    |> then(&if(is_nil(user_id), do: Map.put(&1, "walk_in", true), else: &1))
  end

  defp member(_context, nil), do: {:error, :terminal_member_required}

  # The member (a client or, ADR-272, a guest of the box). A buyer without a
  # finance profile yet gets one, as a package sold at the desk would.
  defp member(context, user_id) do
    case Finance.get_member_profile(context, user_id) do
      %{membership: %{}} ->
        {:ok, user_id}

      _none ->
        with role when not is_nil(role) <-
               Organizations.buyer_role(context, user_id) || {:error, :not_found},
             {:ok, _membership} <-
               UpdateFinanceMember.call(context, user_id, %{
                 "status" => "active",
                 "signup_source" => "direct"
               }) do
          {:ok, user_id}
        end
    end
  end

  defp open_invoice(context, user_id, invoice_id) do
    case Finance.get_member_profile(context, user_id) do
      %{invoices: invoices} ->
        case Enum.find(invoices, &(&1.id == invoice_id)) do
          %{status: status, balance_due_cents: balance} = invoice
          when status in @open_invoice_statuses and balance > 0 ->
            {:ok, invoice}

          %{} ->
            {:error, :invoice_not_payable}

          nil ->
            {:error, :not_found}
        end

      _none ->
        {:error, :not_found}
    end
  end

  defp at_most(amount, limit) when is_integer(amount) and amount > 0 and amount <= limit, do: :ok
  defp at_most(_amount, _limit), do: {:error, :invalid_payment_amount}

  defp package_for_desk(context, package_id) do
    package =
      case Finance.get_package(context, package_id) do
        {:ok, %{} = package} -> package
        %{id: _id} = package -> package
        _missing -> nil
      end

    case package do
      %{active: true} -> {:ok, package}
      %{} -> {:error, :package_inactive}
      nil -> {:error, :not_found}
    end
  end

  defp package_currency(context, package),
    do: Map.get(package, :currency) || business_currency(context)

  defp invoice_description(invoice) do
    first =
      case invoice[:lines] do
        [%{description: text} | _] when is_binary(text) -> " · " <> text
        _none -> ""
      end

    (invoice.invoice_number || "") <> first
  end

  defp business_currency(context) do
    case Fiscal.identity_status(context) do
      %{identity: %{currency: currency}} when is_binary(currency) -> currency
      _none -> "EUR"
    end
  end

  @doc "What the terminal app returned through the phone."
  def record_result(context, params),
    do: context |> Terminal.record_result(params, now()) |> decorated(context)

  def get(context, id), do: context |> Terminal.get(id, now()) |> decorated(context)

  def cancel(context, id), do: context |> Terminal.cancel(id, now()) |> decorated(context)

  defp decorated({:ok, payment}, context), do: {:ok, decorate(context, payment)}
  defp decorated(error, _context), do: error

  @doc """
  ADR-272: the payment with its fiscal document (number, kind, total and
  the state of its transmission to the tax authority) and, for a walk-in,
  the open link of its receipt for the QR.
  """
  def decorate(context, payment) do
    Map.put(payment, :document, document(context, payment))
  end

  defp document(context, %{fiscal_document_id: id} = payment) when is_binary(id) do
    case Fiscal.get_document(context, id) do
      nil ->
        nil

      document ->
        transmission =
          context |> FiscalReporting.for_documents([document.id]) |> Map.get(document.id)

        %{
          id: document.id,
          kind: document.kind,
          number: document.number,
          gross_cents: document.gross_cents,
          currency: document.currency,
          issued_at: document.issued_at,
          authority: transmission && transmission.authority,
          transmission_status: transmission && transmission.status,
          receipt_url: if(is_nil(payment.user_id), do: ReceiptLinks.url(context, document))
        }
    end
  end

  defp document(_context, _payment), do: nil

  @doc """
  ADR-272: «Αποστολή με email» of a Tap to Pay payment's receipt from the
  result screen (ADR-265's document email). `to` is required for a walk-in;
  for a member it defaults to their account's email. Idempotent by
  `idempotency_key`.
  """
  def email_receipt(context, id, params) do
    with {:ok, payment} <- Terminal.get(context, id, now()),
         {:ok, document_id} <- document_id(payment),
         {:ok, to} <- receipt_address(params[:to], payment.user_id) do
      FiscalDocumentRendering.email(context, document_id, %{
        "to" => to,
        "idempotency_key" => params[:idempotency_key],
        "language" => params[:language]
      })
    end
  end

  defp document_id(%{fiscal_document_id: id}) when is_binary(id), do: {:ok, id}
  defp document_id(_payment), do: {:error, :no_document}

  defp receipt_address(to, user_id) do
    cond do
      is_binary(to) and String.trim(to) != "" -> {:ok, String.trim(to)}
      is_binary(user_id) -> account_email(user_id)
      true -> {:error, :no_recipient}
    end
  end

  # A held or imported profile may carry a placeholder address that never
  # receives mail (RFC 2606 `.invalid`).
  defp account_email(user_id) do
    case Identity.find_by_id(user_id) do
      %{email: email} when is_binary(email) and email != "" ->
        if String.ends_with?(email, ".invalid"), do: {:error, :no_recipient}, else: {:ok, email}

      _none ->
        {:error, :no_recipient}
    end
  end

  @doc """
  Dev/test only: the sandbox terminal app takes (or refuses) the card;
  `extras` may add a tip and a card surcharge (ADR-264).
  """
  def sandbox_complete(context, id, outcome, extras \\ %{}) do
    with {:ok, reference, transaction_id} <-
           Terminal.sandbox_transaction(context, id, outcome, extras) do
      context
      |> Terminal.record_result(
        %{
          reference: reference,
          status: if(outcome == "succeeded", do: "success", else: "fail"),
          transaction_id: transaction_id
        },
        now()
      )
      |> decorated(context)
    end
  end

  defp now, do: DateTime.utc_now()
end
