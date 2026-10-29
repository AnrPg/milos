defmodule Palee.Fiscal.Domain.TseTransaction do
  @moduledoc """
  A German receipt as a TSE transaction (ADR-251): the process data that
  fiskaly SIGN DE v2 signs (`standard_v1` receipt, process type
  `Kassenbeleg-V1` of DSFinV-K), and what the receipt must print. Pure.

  Amounts are gross per VAT rate and per payment type, as decimal strings
  (`"12.34"`); a credit note's amounts are negative. VAT rates use
  DSFinV-K's names: 19 % `NORMAL`, 7 % `REDUCED_1`, 10.7 % `SPECIAL_RATE_1`,
  5.5 % `SPECIAL_RATE_2`, 0 % `NULL`.

  The printed data follow §6 KassenSichV: the start and end time, the
  transaction number, the signature counter, the serial number of the
  till (client) and of the TSE, the signature and its algorithm, the time
  format and the TSE's public key, plus the DSFinV-K QR code (Appendix I).

  Sources: fiskaly SIGN DE v2 API (https://workspace.fiskaly.com/specs/sign-de-v2.json),
  KassenSichV §6 (https://www.gesetze-im-internet.de/kassensichv/__6.html),
  DSFinV-K (https://www.bzst.de/DE/Unternehmen/Aussenpruefungen/DigitaleSchnittstelleFinV/digitaleschnittstellefinv_node.html).
  """

  @vat_rates %{1900 => "NORMAL", 700 => "REDUCED_1", 1070 => "SPECIAL_RATE_1", 550 => "SPECIAL_RATE_2", 0 => "NULL"}
  # DSFinV-K order of the QR code's amounts.
  @rate_order ["NORMAL", "REDUCED_1", "SPECIAL_RATE_1", "SPECIAL_RATE_2", "NULL"]

  @doc """
  `{:ok, schema}` – the transaction's `schema` for its FINISHED revision –
  or `{:error, :unsupported_vat_rate}`.
  """
  def schema(document) do
    sign = if document.kind == "credit_note", do: -1, else: 1

    with {:ok, rates} <- amounts_per_vat_rate(document.tax_breakdown, sign) do
      {:ok,
       %{
         "standard_v1" => %{
           "receipt" => %{
             "receipt_type" => "RECEIPT",
             "amounts_per_vat_rate" => rates,
             "amounts_per_payment_type" => [
               %{
                 "payment_type" => payment_type(document.payment_method),
                 "amount" => decimal(sign * document.gross_cents),
                 "currency_code" => document.currency
               }
             ]
           }
         }
       }}
    end
  end

  defp amounts_per_vat_rate(groups, sign) do
    groups
    |> Enum.reduce_while({:ok, %{}}, fn group, {:ok, acc} ->
      rate = field(group, :rate_bp)

      case Map.fetch(@vat_rates, rate) do
        {:ok, name} ->
          {:cont, {:ok, Map.update(acc, name, field(group, :gross_cents), &(&1 + field(group, :gross_cents)))}}

        :error ->
          {:halt, {:error, :unsupported_vat_rate}}
      end
    end)
    |> case do
      {:ok, sums} ->
        {:ok,
         @rate_order
         |> Enum.filter(&Map.has_key?(sums, &1))
         |> Enum.map(&%{"vat_rate" => &1, "amount" => decimal(sign * Map.fetch!(sums, &1))})}

      error ->
        error
    end
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  @doc "DSFinV-K payment type: cash is `CASH`, everything else `NON_CASH`."
  def payment_type("cash"), do: "CASH"
  def payment_type(_method), do: "NON_CASH"

  @doc "Cents as a decimal string with two decimals (`-1234` → `\"-12.34\"`)."
  def decimal(cents) when is_integer(cents) do
    sign = if cents < 0, do: "-", else: ""
    cents = abs(cents)

    sign <>
      Integer.to_string(div(cents, 100)) <>
      "." <> String.pad_leading(Integer.to_string(rem(cents, 100)), 2, "0")
  end

  @doc """
  What the receipt prints (label, value), in German as the law asks. A
  receipt recorded as a TSE failure prints that instead (AEAO zu §146a).
  """
  def print_lines(%{status: "device_failed"} = signature) do
    [{"TSE", "TSE ausgefallen"}, {"Ausfall seit", iso(signature.failed_at)}]
  end

  def print_lines(%{status: "signed"} = signature) do
    [
      {"TSE-Seriennummer", signature.unit_serial},
      {"Kassen-Seriennummer", signature.register_serial},
      {"Transaktionsnummer", to_string(signature.transaction_number)},
      {"Signaturzähler", to_string(signature.signature_counter)},
      {"Start", iso(signature.started_at_device)},
      {"Ende", iso(signature.finished_at_device)},
      {"Signaturalgorithmus", signature.signature_algorithm},
      {"Zeitformat", signature.time_format},
      {"Signatur", signature.signature_value}
    ]
    |> Enum.reject(fn {_label, value} -> value in [nil, ""] end)
  end

  def print_lines(_pending), do: [{"TSE", "Signatur ausstehend"}]

  defp iso(nil), do: nil
  defp iso(%DateTime{} = at), do: at |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
