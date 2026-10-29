defmodule Palee.Fiscal.Domain.RksvReceipt do
  @moduledoc """
  An Austrian receipt for the RKSV signature creation unit (ADR-251): the
  amounts fiskaly SIGN AT signs, and the machine-readable code
  (`qr_code_data`) every receipt prints. Pure.

  RKSV sorts amounts into five rate groups: `Satz-Normal` (20 %),
  `Satz-Ermaessigt-1` (10 %), `Satz-Ermaessigt-2` (13 %), `Satz-Null`
  (0 %) and `Satz-Besonders` (19 %). fiskaly names them `STANDARD`,
  `REDUCED_1`, `REDUCED_2`, `ZERO` and `SPECIAL`. A credit note's amounts
  are negative; a null receipt (Nullbeleg) has none.

  The machine-readable code (Detailspezifikation of the RKSV, Z 12) is

      _R1-AT1_<Kassen-ID>_<Belegnummer>_<Datum-Uhrzeit>_<Betrag-Satz-Normal>
      _<Betrag-Satz-Ermaessigt-1>_<Betrag-Satz-Ermaessigt-2>_<Betrag-Satz-Null>
      _<Betrag-Satz-Besonders>_<Stand-Umsatz-Zaehler>_<Zertifikat-Seriennummer>
      _<Sig-Voriger-Beleg>_<Signaturwert>

  and when the signature creation unit has failed its signature value is
  the Base64 of "Sicherheitseinrichtung ausgefallen", which the receipt
  must also print in plain text (RKSV §17).

  Sources: RKSV (https://www.ris.bka.gv.at/GeltendeFassung.wxe?Abfrage=Bundesnormen&Gesetzesnummer=20009390),
  BMF Registrierkassen (https://www.bmf.gv.at/themen/steuern/fuer-unternehmen/registrierkassen.html),
  fiskaly SIGN AT (https://workspace.fiskaly.com/api/rksv/v1/).
  """

  @vat_rates %{
    2000 => "STANDARD",
    1000 => "REDUCED_1",
    1300 => "REDUCED_2",
    0 => "ZERO",
    1900 => "SPECIAL"
  }
  @rate_order ["STANDARD", "REDUCED_1", "REDUCED_2", "ZERO", "SPECIAL"]
  @failed_marker "Sicherheitseinrichtung ausgefallen"
  @failed_signature Base.encode64(@failed_marker)

  def failed_marker, do: @failed_marker
  def failed_signature, do: @failed_signature

  @doc "`{:ok, schema}` for a receipt or credit note, or `{:error, :unsupported_vat_rate}`."
  def schema(document) do
    sign = if document.kind == "credit_note", do: -1, else: 1

    with {:ok, rates} <- amounts(document.tax_breakdown, sign) do
      {:ok,
       %{
         "standard_v1" => %{
           "receipt" => %{
             "amounts_per_vat_rate" => rates,
             "amounts_per_payment_type" => [
               %{
                 "payment_type" =>
                   if(document.payment_method == "cash", do: "CASH", else: "NON_CASH"),
                 "amount" => decimal(sign * document.gross_cents),
                 "currency_code" => document.currency
               }
             ]
           }
         }
       }}
    end
  end

  @doc "The schema of a null receipt (Nullbeleg): every amount zero."
  def null_schema do
    %{
      "standard_v1" => %{
        "receipt" => %{
          "amounts_per_vat_rate" => [%{"vat_rate" => "STANDARD", "amount" => "0.00"}],
          "amounts_per_payment_type" => [
            %{"payment_type" => "CASH", "amount" => "0.00", "currency_code" => "EUR"}
          ]
        }
      }
    }
  end

  defp amounts(groups, sign) do
    groups
    |> Enum.reduce_while({:ok, %{}}, fn group, {:ok, acc} ->
      rate = field(group, :rate_bp)
      gross = field(group, :gross_cents)

      case Map.fetch(@vat_rates, rate) do
        {:ok, name} -> {:cont, {:ok, Map.update(acc, name, gross, &(&1 + gross))}}
        :error -> {:halt, {:error, :unsupported_vat_rate}}
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

  def decimal(cents), do: Palee.Fiscal.Domain.TseTransaction.decimal(cents)

  @doc """
  The parts of a machine-readable code, or `{:error, :invalid_code}`:
  `%{suite, register_id, receipt_number, signed_at, amounts, turnover_counter,
  certificate_serial, previous_signature, signature, device_failed}`.
  """
  def parse_code(code) when is_binary(code) do
    case String.split(code, "_") do
      [
        "",
        "R1-AT" <> _ = suite,
        register,
        number,
        at,
        normal,
        reduced_1,
        reduced_2,
        zero,
        special,
        counter,
        certificate,
        previous,
        signature
      ] ->
        {:ok,
         %{
           suite: suite,
           register_id: register,
           receipt_number: number,
           signed_at: at,
           amounts: %{
             "STANDARD" => normal,
             "REDUCED_1" => reduced_1,
             "REDUCED_2" => reduced_2,
             "ZERO" => zero,
             "SPECIAL" => special
           },
           turnover_counter: counter,
           certificate_serial: certificate,
           previous_signature: previous,
           signature: signature,
           device_failed: signature == @failed_signature
         }}

      _other ->
        {:error, :invalid_code}
    end
  end

  def parse_code(_code), do: {:error, :invalid_code}

  @doc "What the receipt prints: the code (as QR) and, after an outage, the marker text."
  def print_lines(%{qr_code_data: code} = signature) when is_binary(code) do
    failed =
      signature.status == "device_failed" or
        match?({:ok, %{device_failed: true}}, parse_code(code))

    ([{"Kassen-ID", signature.register_serial}, {"Belegnummer", signature.receipt_number}] ++
       if(failed, do: [{"Hinweis", @failed_marker}], else: []) ++ [{"QR", code}])
    |> Enum.reject(fn {_label, value} -> value in [nil, ""] end)
  end

  def print_lines(_unsigned), do: [{"Hinweis", @failed_marker}]
end
