defmodule Palee.Finance.Domain.ReceivedPayment do
  @moduledoc """
  ADR-222: money staff received from a client at the desk, and the document
  it leaves behind. Pure rules; the store does the writing.

  Which document a payment leaves follows the box's billing setup
  (`finance_settings.document_mode`), never the screen that sent it:

    * paying an open invoice settles that invoice, whatever the mode;
    * otherwise a box in `"receipt"` mode issues a paid receipt;
    * and a box in `"invoice"` mode issues a paid invoice.
  """

  @methods ["cash", "card_manual", "bank_transfer", "other"]
  # ADR-246/249: recorded by Palee after the provider confirmed a payment
  # (online, or a card tapped on the Viva.com Terminal app); never offered
  # at the desk.
  @online_methods ["online", "card_terminal"]
  @document_modes ["invoice", "receipt"]

  @type document :: :settle_invoice | :receipt | :invoice

  @doc "The ways money can reach the box at the desk."
  def methods, do: @methods

  @doc "What the payment leaves behind."
  @spec document(String.t() | nil, String.t() | nil) :: document()
  def document(_mode, invoice_id) when is_binary(invoice_id) and invoice_id != "",
    do: :settle_invoice

  def document("receipt", _invoice_id), do: :receipt
  def document(_mode, _invoice_id), do: :invoice

  @doc "The `document_kind` stored on an invoice row the payment creates."
  def document_kind(:receipt), do: "receipt"
  def document_kind(:invoice), do: "invoice"

  def document_modes, do: @document_modes

  @doc """
  Checks the request before anything is written. A retry must carry the same
  `idempotency_key`, so one press never records the money twice.
  """
  def validate(params) when is_map(params) do
    cond do
      blank?(params["idempotency_key"]) ->
        {:error, :idempotency_key_required}

      params["payment_method"] not in (@methods ++ @online_methods) ->
        {:error, :invalid_payment_method}

      not positive_integer?(params["amount_cents"]) ->
        {:error, :invalid_payment_amount}

      true ->
        :ok
    end
  end

  @doc """
  A new document needs to say what the money was for: a πακέτο συνδρομής or
  a description typed by staff.
  """
  def validate_purpose(:settle_invoice, _params), do: :ok

  def validate_purpose(_document, params) do
    if blank?(params["membership_package_subscription_id"]) and blank?(params["description"]),
      do: {:error, :payment_purpose_required},
      else: :ok
  end

  defp positive_integer?(value) when is_integer(value), do: value > 0

  defp positive_integer?(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int > 0
      _other -> false
    end
  end

  defp positive_integer?(_value), do: false

  defp blank?(value), do: value in [nil, ""] or (is_binary(value) and String.trim(value) == "")
end
