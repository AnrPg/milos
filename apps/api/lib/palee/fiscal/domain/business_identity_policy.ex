defmodule Palee.Fiscal.Domain.BusinessIdentityPolicy do
  @moduledoc """
  Validation of a business's legal identity (ADR-240): the country is
  supported, tax ids pass their country's checks, the VAT scheme and the
  document language are known, text fields are bounded. Returns normalised
  attributes; completeness is reported separately
  (`CountryProfile.missing_fields/2`) so a gym can save a half-filled form.
  """

  alias Palee.Fiscal.Domain.{CountryProfile, TaxId}

  @vat_schemes ~w(standard small_business exempt)
  @text_fields ~w(legal_name trade_name tax_office activity_code street building_number
                  postal_code city region email phone)a
  @id_fields ~w(tax_id vat_number registration_number)a
  @max_text 200

  def vat_schemes, do: @vat_schemes

  @doc "Fields a caller may set."
  def fields,
    do:
      [:country_code, :vat_scheme, :document_language, :branch_code, :fiscal_year_start_month] ++
        @text_fields ++ @id_fields

  @doc """
  `{:ok, attrs}` with normalised values, or `{:error, {:invalid_fields,
  %{field => reason}}}`. `current` is the saved identity (or `%{}`), so a
  partial update is checked against the whole.
  """
  def validate(current, changes) do
    merged = Map.merge(current, Map.take(changes, fields()))
    country = merged |> Map.get(:country_code) |> upcase()

    errors =
      %{}
      |> check_country(country)
      |> check_scheme(merged[:vat_scheme] || "standard")
      |> check_language(country, merged[:document_language])
      |> check_branch(merged[:branch_code])
      |> check_year_start(merged[:fiscal_year_start_month])
      |> check_texts(merged)

    # An unsupported country has no tax id rules to check against.
    {ids, errors} =
      if CountryProfile.supported?(country),
        do: check_ids(country, merged, errors),
        else: {%{}, errors}

    if errors == %{} do
      currency = CountryProfile.fetch!(country).currency

      {:ok,
       merged
       |> Map.take(fields())
       |> Map.merge(ids)
       |> Map.new(fn
         {key, value} when key in @text_fields -> {key, clean(value)}
         other -> other
       end)
       |> Map.merge(%{
         country_code: country,
         currency: currency,
         vat_scheme: merged[:vat_scheme] || "standard",
         branch_code: merged[:branch_code] || 0,
         fiscal_year_start_month: merged[:fiscal_year_start_month] || 1
       })}
    else
      {:error, {:invalid_fields, errors}}
    end
  end

  defp check_country(errors, country) do
    if CountryProfile.supported?(country),
      do: errors,
      else: Map.put(errors, :country_code, :unsupported_country)
  end

  defp check_scheme(errors, scheme) when scheme in @vat_schemes, do: errors
  defp check_scheme(errors, _scheme), do: Map.put(errors, :vat_scheme, :invalid)

  defp check_language(errors, _country, nil), do: errors

  defp check_language(errors, country, language) do
    case CountryProfile.fetch(country) do
      {:ok, %{languages: languages}} ->
        if language in languages, do: errors, else: Map.put(errors, :document_language, :invalid)

      _unsupported ->
        errors
    end
  end

  defp check_branch(errors, nil), do: errors

  defp check_branch(errors, code) when is_integer(code) and code >= 0 and code <= 9_999,
    do: errors

  defp check_branch(errors, _code), do: Map.put(errors, :branch_code, :invalid)

  defp check_year_start(errors, nil), do: errors
  defp check_year_start(errors, month) when month in 1..12, do: errors
  defp check_year_start(errors, _month), do: Map.put(errors, :fiscal_year_start_month, :invalid)

  defp check_texts(errors, merged) do
    Enum.reduce(@text_fields, errors, fn field, errors ->
      case merged[field] do
        nil ->
          errors

        value when is_binary(value) ->
          if String.length(value) <= @max_text,
            do: errors,
            else: Map.put(errors, field, :too_long)

        _other ->
          Map.put(errors, field, :invalid)
      end
    end)
    |> check_email(merged[:email])
  end

  defp check_email(errors, nil), do: errors

  defp check_email(errors, email) when is_binary(email) do
    if String.trim(email) == "" or
         Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, String.trim(email)),
       do: errors,
       else: Map.put(errors, :email, :invalid)
  end

  defp check_email(errors, _email), do: Map.put(errors, :email, :invalid)

  defp check_ids(country, merged, errors) do
    Enum.reduce(@id_fields, {%{}, errors}, fn field, {ids, errors} ->
      case TaxId.normalize(merged[field]) do
        nil ->
          {Map.put(ids, field, nil), errors}

        _value ->
          case TaxId.validate(country, field, merged[field]) do
            {:ok, normalized} -> {Map.put(ids, field, normalized), errors}
            {:error, reason} -> {ids, Map.put(errors, field, reason)}
          end
      end
    end)
  end

  defp upcase(value) when is_binary(value), do: value |> String.trim() |> String.upcase()
  defp upcase(_value), do: nil

  defp clean(nil), do: nil

  defp clean(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @doc "Field names whose values differ between two identities (for the journal)."
  def changed_fields(before, after_) do
    fields()
    |> Kernel.++([:currency])
    |> Enum.filter(fn field -> Map.get(before, field) != Map.get(after_, field) end)
    |> Enum.sort()
  end
end
