defmodule Palee.Fiscal.Domain.SignFrReceipt do
  @moduledoc """
  What a French till receipt sends to the signing service (fiskaly SIGN
  FR, ADR-266) and what it prints from the answer. Pure.

  France (CGI art. 286, I-3° bis) asks a till system to keep its sales
  inalterable, secured, kept and archived. Palee's own journal does this
  for every country (ADR-241/242: hash chain, signed head, closings);
  in France each receipt and credit note is also recorded at fiskaly
  SIGN FR, which signs it into its own sequence and archives it.

  `schema/3` is the request: the document's numbers, lines, VAT
  breakdown and payment as plain data, the fiskaly record of the
  corrected receipt (credit notes) and whether the receipt is sent late
  (`offline`, after an outage: fiskaly records it as issued offline).

  `print_lines/1` prints the sequence number and a short form of the
  signature; a receipt not yet recorded prints that it is waiting.
  """

  @waiting "Enregistrement fiskaly en attente"

  @doc """
  `{:ok, schema}` or `{:error, :not_a_receipt | :original_not_signed}`.
  `original` is the signature row of the corrected receipt (credit notes).
  """
  def schema(document, original, offline?) do
    cond do
      document.kind not in ["receipt", "credit_note"] ->
        {:error, :not_a_receipt}

      document.kind == "credit_note" and not signed?(original) ->
        {:error, :original_not_signed}

      true ->
        {:ok,
         %{
           kind: document.kind,
           number: document.number,
           issue_date: document.issue_date,
           issued_at: document.issued_at,
           currency: document.currency,
           payment_method: document.payment_method,
           net_cents: document.net_cents,
           tax_cents: document.tax_cents,
           gross_cents: document.gross_cents,
           tax_breakdown: document.tax_breakdown,
           lines:
             document.lines
             |> Enum.sort_by(& &1.position)
             |> Enum.map(
               &Map.take(&1, [
                 :position,
                 :description,
                 :quantity,
                 :net_cents,
                 :tax_cents,
                 :gross_cents,
                 :rate_bp,
                 :tax_category,
                 :exemption_reason,
                 :source_type
               ])
             ),
           original_record_id: original && original.receipt_number,
           offline: offline?
         }}
    end
  end

  defp signed?(%{status: "signed", receipt_number: id}) when is_binary(id), do: true
  defp signed?(_original), do: false

  @doc "What the receipt prints: `[{label, value}]`."
  def print_lines(%{status: "signed"} = signature) do
    [
      {"N° séquence fiskaly", signature.transaction_number && to_string(signature.transaction_number)},
      {"Signature", short(signature.signature_value)}
    ]
    |> Enum.reject(fn {_label, value} -> value in [nil, ""] end)
  end

  def print_lines(_unsigned), do: [{"Note", @waiting}]

  defp short(value) when is_binary(value) and byte_size(value) > 16,
    do: String.slice(value, 0, 8) <> "…" <> String.slice(value, -8, 8)

  defp short(value), do: value
end
