defmodule Palee.Application.Fiscal.ReceiptLinks do
  @moduledoc """
  ADR-272: the walk-in's receipt as a QR on the staff phone. A walk-in has
  no account and often no email, so the result screen shows a QR of a
  signed, expiring link to the receipt; the customer scans it and keeps the
  receipt on their phone.

  * Only for a receipt with no buyer printed on it; the caller offers it
    for a walk-in's payment only (a member's receipt goes by email).
  * The token is signed (`Plug.Crypto.sign/4`) over the business and the
    document; it cannot be pointed at another document or business, and
    it expires after 90 days.
  * The page is the document's printable HTML (ADR-245), in its language.
  """

  alias Palee.Application.Fiscal.FiscalDocumentRendering
  alias Palee.Fiscal

  @salt "palee-fiscal-receipt-link"
  @max_age 90 * 24 * 3_600

  def max_age_seconds, do: @max_age

  @doc "The public link of a walk-in's receipt, or nil for a document with a buyer."
  def url(context, document) do
    if open_receipt?(document) do
      base = Application.get_env(:palee, :public_base_url, "")
      base <> "/api/public/receipts/" <> token(context.organization_id, document.id)
    end
  end

  @doc "Whether a document may be on an open link: a receipt with no buyer."
  def open_receipt?(%{kind: kind, buyer: buyer}),
    do: kind == "receipt" and not has_buyer?(buyer)

  def open_receipt?(_document), do: false

  defp has_buyer?(buyer) when is_map(buyer),
    do: Enum.any?(buyer, fn {_key, value} -> value not in [nil, "", %{}, []] end)

  defp has_buyer?(_buyer), do: false

  def token(organization_id, document_id),
    do: Plug.Crypto.sign(secret(), @salt, {organization_id, document_id}, max_age: @max_age)

  @doc """
  The receipt's HTML for a token: `{:ok, %{content, content_type}}` or
  `{:error, :not_found}` (bad or expired token, or no longer an open receipt).
  """
  def render(token) when is_binary(token) do
    with {:ok, {organization_id, document_id}} <-
           Plug.Crypto.verify(secret(), @salt, token, max_age: @max_age),
         context = %{organization_id: organization_id},
         %{} = document <- Fiscal.get_document(context, document_id),
         true <- open_receipt?(document),
         {:ok, rendered} <- FiscalDocumentRendering.call(context, document_id, :html) do
      {:ok, rendered}
    else
      _invalid -> {:error, :not_found}
    end
  end

  def render(_token), do: {:error, :not_found}

  defp secret do
    case Application.get_env(:palee, :payment_terminal_secret) do
      secret when is_binary(secret) and byte_size(secret) >= 32 ->
        secret

      _none ->
        :palee
        |> Application.get_env(PaleeWeb.Endpoint, [])
        |> Keyword.get(:secret_key_base, "palee-dev-receipts")
    end
  end
end
