defmodule Palee.Fiscal.Domain.PeppolId do
  @moduledoc """
  Peppol participant identifiers (ADR-250): `"<scheme>:<identifier>"`,
  where the scheme is an ICD code of the Peppol Code Lists (EAS, used as
  `schemeID` of `cbc:EndpointID`). Pure.

  Belgium uses `0208`, the enterprise number of the Crossroads Bank for
  Enterprises (KBO/BCE: ten digits, the last two being 97 minus the first
  eight modulo 97); a Belgian VAT number is `BE` + the enterprise number,
  so a Belgian buyer's identifier can be derived from its VAT number.
  `9925` (VAT number) is accepted as well.

  Sources: Peppol Code Lists, Participant identifier schemes
  (https://docs.peppol.eu/edelivery/codelists/) and BOSA's
  "Peppol in Belgium" (https://efacture.belgium.be/en/peppol).
  """

  @schemes %{
    "0208" => :be_enterprise,
    "9925" => :be_vat,
    "0088" => :gln,
    "0106" => :nl_kvk,
    "0190" => :nl_oin,
    "9930" => :de_vat,
    "0204" => :de_leitweg,
    "9914" => :at_vat,
    "0007" => :se_org,
    "0192" => :no_org,
    "0184" => :dk_cvr,
    "0009" => :fr_siret,
    "0225" => :fr_siren,
    "9915" => :at_gov,
    "0060" => :duns,
    "0151" => :au_abn
  }
  @max_identifier 50

  @doc "The ICD scheme codes accepted, sorted."
  def schemes, do: @schemes |> Map.keys() |> Enum.sort()

  @doc """
  `{:ok, %{scheme, identifier}}` for `"0208:0123456789"` (or a map with
  `scheme` and `identifier`), normalised; `{:error, :invalid_peppol_id}`.
  """
  def parse(%{scheme: scheme, identifier: identifier}), do: parse("#{scheme}:#{identifier}")

  def parse(value) when is_binary(value) do
    with [scheme, identifier] <- value |> String.trim() |> String.split(":", parts: 2),
         true <- is_map_key(@schemes, scheme),
         identifier = normalize(scheme, identifier),
         :ok <- check(scheme, identifier) do
      {:ok, %{scheme: scheme, identifier: identifier}}
    else
      _ -> {:error, :invalid_peppol_id}
    end
  end

  def parse(_value), do: {:error, :invalid_peppol_id}

  @doc "`\"scheme:identifier\"`."
  def format(%{scheme: scheme, identifier: identifier}), do: "#{scheme}:#{identifier}"

  @doc """
  The buyer's Peppol identifier: its own `peppol_id` when given, else the
  `0208` enterprise number derived from a Belgian VAT number (or Belgian
  tax id). `{:ok, id}` or `{:error, :buyer_peppol_id_missing}`.
  """
  def for_party(party) when is_map(party) do
    cond do
      is_binary(party[:peppol_id]) ->
        parse(party[:peppol_id])

      be_number(party[:vat_number]) ->
        {:ok, %{scheme: "0208", identifier: be_number(party[:vat_number])}}

      party[:country_code] == "BE" and be_number(party[:tax_id]) ->
        {:ok, %{scheme: "0208", identifier: be_number(party[:tax_id])}}

      true ->
        {:error, :buyer_peppol_id_missing}
    end
  end

  def for_party(_party), do: {:error, :buyer_peppol_id_missing}

  @doc "The ten-digit Belgian enterprise number in a VAT number or tax id, when valid."
  def be_number(value) when is_binary(value) do
    digits =
      value
      |> String.upcase()
      |> String.replace_prefix("BE", "")
      |> String.replace(~r/[\s.\-]/, "")

    digits = if String.length(digits) == 9, do: "0" <> digits, else: digits

    if Regex.match?(~r/^[01]\d{9}$/, digits) and enterprise_checksum?(digits),
      do: digits,
      else: nil
  end

  def be_number(_value), do: nil

  defp enterprise_checksum?(digits) do
    {base, check} = String.split_at(digits, 8)
    97 - rem(String.to_integer(base), 97) == String.to_integer(check)
  end

  defp normalize("0208", identifier), do: be_number(identifier) || identifier
  defp normalize("9925", identifier), do: identifier |> String.upcase() |> String.replace(" ", "")
  defp normalize(_scheme, identifier), do: String.trim(identifier)

  defp check("0208", identifier) do
    if be_number(identifier) == identifier, do: :ok, else: :error
  end

  defp check("9925", "BE" <> rest) do
    if be_number(rest), do: :ok, else: :error
  end

  defp check("9925", _identifier), do: :error

  defp check(_scheme, identifier) do
    if identifier != "" and String.length(identifier) <= @max_identifier and
         Regex.match?(~r/^[A-Za-z0-9.\-_:]+$/, identifier),
       do: :ok,
       else: :error
  end
end
