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

  alias Palee.Application.GoLive
  alias Palee.Finance
  alias Palee.Fiscal
  alias Palee.Payments.Terminal
  alias Palee.Shop

  @open_invoice_statuses ~w(issued partially_paid overdue)
  @charge_categories ~w(product personal_training event other)

  def charge_categories, do: @charge_categories

  @doc "Whether the business can take Tap to Pay now."
  def availability(context), do: %{available: Terminal.available?(context)}

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
         :ok <- GoLive.check_payment(context, purpose.user_id || user_id) do
      Terminal.start(
        context,
        %{
          purpose_type: params[:purpose],
          purpose_id: purpose.purpose_id,
          user_id: purpose.user_id,
          amount_cents: params[:amount_cents],
          currency: purpose.currency,
          description: purpose.description,
          metadata: purpose[:metadata] || %{},
          idempotency_key: params[:idempotency_key],
          created_by_id: Map.get(context, :user_id)
        },
        now()
      )
    end
  end

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

  # ADR-264: a walk-in (no member) may pay a free sale too.
  defp free_sale_payer(_context, nil), do: {:ok, nil}
  defp free_sale_payer(context, user_id), do: member(context, user_id)

  defp free_sale_metadata(user_id, category) do
    %{}
    |> then(&if(category, do: Map.put(&1, "charge_category", category), else: &1))
    |> then(&if(is_nil(user_id), do: Map.put(&1, "walk_in", true), else: &1))
  end

  defp resolve(_context, _purpose, _params), do: {:error, :invalid_payment_purpose}

  defp member(_context, nil), do: {:error, :terminal_member_required}

  defp member(context, user_id) do
    case Finance.get_member_profile(context, user_id) do
      %{membership: %{}} -> {:ok, user_id}
      _none -> {:error, :not_found}
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
  def record_result(context, params), do: Terminal.record_result(context, params, now())

  def get(context, id), do: Terminal.get(context, id, now())

  def cancel(context, id), do: Terminal.cancel(context, id, now())

  @doc """
  Dev/test only: the sandbox terminal app takes (or refuses) the card;
  `extras` may add a tip and a card surcharge (ADR-264).
  """
  def sandbox_complete(context, id, outcome, extras \\ %{}) do
    with {:ok, reference, transaction_id} <-
           Terminal.sandbox_transaction(context, id, outcome, extras) do
      Terminal.record_result(
        context,
        %{
          reference: reference,
          status: if(outcome == "succeeded", do: "success", else: "fail"),
          transaction_id: transaction_id
        },
        now()
      )
    end
  end

  defp now, do: DateTime.utc_now()
end
