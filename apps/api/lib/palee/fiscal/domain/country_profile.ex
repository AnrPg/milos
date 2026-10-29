defmodule Palee.Fiscal.Domain.CountryProfile do
  @moduledoc """
  What the law of each supported country asks of a gym's sales (ADR-240).

  A profile is data. Adding a country means adding a profile here and, where
  it has a state system, an adapter behind the matching port; the domain does
  not change.

    * `currency` – ISO 4217 currency of documents;
    * `languages` – document languages, the first is the default;
    * `tax_system` – `:vat` or `:sales_tax` (US: rates per state and city);
    * `authority` – where every document is reported: `:mydata` or `:none`;
    * `register` – `:nf525` (France, Monaco: certified or attested
      inalterable register) or `:standard`; Palee keeps the inalterable
      journal everywhere (ADR-242), the profile says which rules are law;
    * `till_device` – signing device for money taken at a till: `:tse`
      (Germany, KassenSichV), `:rksv` (Austria) or `:none`;
    * `einvoicing` – B2B e-invoicing obligations: `:peppol` (Belgium 2026),
      `:en16931` (Germany: receive since 2025, issue from 2027),
      `:fr_einvoicing` (France: receive from Sept 2026, issue from 2027);
    * `required` – identity fields a complete identity needs;
      `{:one_of, fields}` asks for at least one of them;
    * `tax_office` – whether the tax office (ΔΟΥ) is printed;
    * `retention_years` – the statutory minimum; Palee keeps 10 everywhere.

  Sources: `docs/plans/government-fiscal-integrations.md`.
  """

  @base_required [:legal_name, :street, :postal_code, :city]

  @profiles %{
    "GR" => %{
      currency: "EUR",
      languages: ["el", "en"],
      tax_system: :vat,
      authority: :mydata,
      register: :standard,
      till_device: :none,
      einvoicing: [],
      required: [:tax_id, :tax_office],
      tax_office: true,
      retention_years: 5
    },
    "CY" => %{
      currency: "EUR",
      languages: ["el", "en"],
      tax_system: :vat,
      authority: :none,
      register: :standard,
      till_device: :none,
      einvoicing: [],
      required: [:tax_id],
      tax_office: false,
      retention_years: 6
    },
    "DE" => %{
      currency: "EUR",
      languages: ["de", "en"],
      tax_system: :vat,
      authority: :none,
      register: :standard,
      till_device: :tse,
      einvoicing: [:en16931],
      required: [{:one_of, [:tax_id, :vat_number]}],
      tax_office: false,
      retention_years: 10
    },
    "AT" => %{
      currency: "EUR",
      languages: ["de", "en"],
      tax_system: :vat,
      authority: :none,
      register: :standard,
      till_device: :rksv,
      einvoicing: [],
      required: [{:one_of, [:tax_id, :vat_number]}],
      tax_office: false,
      retention_years: 7
    },
    "CH" => %{
      currency: "CHF",
      languages: ["de", "fr", "it", "en"],
      tax_system: :vat,
      authority: :none,
      register: :standard,
      till_device: :none,
      einvoicing: [],
      required: [],
      tax_office: false,
      retention_years: 10
    },
    "LI" => %{
      currency: "CHF",
      languages: ["de", "en"],
      tax_system: :vat,
      authority: :none,
      register: :standard,
      till_device: :none,
      einvoicing: [],
      required: [],
      tax_office: false,
      retention_years: 10
    },
    "LU" => %{
      currency: "EUR",
      languages: ["fr", "de", "en"],
      tax_system: :vat,
      authority: :none,
      register: :standard,
      till_device: :none,
      einvoicing: [],
      required: [{:one_of, [:tax_id, :vat_number]}],
      tax_office: false,
      retention_years: 10
    },
    "FR" => %{
      currency: "EUR",
      languages: ["fr", "en"],
      tax_system: :vat,
      authority: :none,
      register: :nf525,
      till_device: :none,
      einvoicing: [:fr_einvoicing],
      required: [:registration_number],
      tax_office: false,
      retention_years: 10
    },
    "BE" => %{
      currency: "EUR",
      languages: ["fr", "nl", "de", "en"],
      tax_system: :vat,
      authority: :none,
      register: :standard,
      till_device: :none,
      einvoicing: [:peppol],
      required: [:tax_id],
      tax_office: false,
      retention_years: 10
    },
    "MC" => %{
      currency: "EUR",
      languages: ["fr", "en"],
      tax_system: :vat,
      authority: :none,
      register: :nf525,
      till_device: :none,
      einvoicing: [],
      required: [:registration_number],
      tax_office: false,
      retention_years: 10
    },
    "GB" => %{
      currency: "GBP",
      languages: ["en"],
      tax_system: :vat,
      authority: :none,
      register: :standard,
      till_device: :none,
      einvoicing: [],
      required: [],
      tax_office: false,
      retention_years: 6
    },
    "US" => %{
      currency: "USD",
      languages: ["en", "es"],
      tax_system: :sales_tax,
      authority: :none,
      register: :standard,
      till_device: :none,
      einvoicing: [],
      required: [:region],
      tax_office: false,
      retention_years: 7
    }
  }

  @retention_years 10

  @doc "ISO 3166-1 alpha-2 codes of the supported countries, sorted."
  def countries, do: @profiles |> Map.keys() |> Enum.sort()

  def supported?(country), do: is_map_key(@profiles, country)

  @doc "`{:ok, profile}` (with `:country`) or `{:error, :unsupported_country}`."
  def fetch(country) when is_map_key(@profiles, country),
    do: {:ok, @profiles |> Map.fetch!(country) |> Map.put(:country, country)}

  def fetch(_country), do: {:error, :unsupported_country}

  def fetch!(country) do
    {:ok, profile} = fetch(country)
    profile
  end

  @doc "How long Palee keeps fiscal data: the longest minimum of any profile."
  def retention_years, do: @retention_years

  @doc "Identity fields every country asks for plus the country's own."
  def required_fields(%{required: required}), do: @base_required ++ required

  @doc """
  Fields still missing from `identity` (a map with atom keys) under the
  profile, as atoms; `{:one_of, [a, b]}` reports `:a_or_b`. A business
  that is not VAT registered (`vat_scheme` other than `standard`) is never
  asked for a VAT number.
  """
  def missing_fields(profile, identity) do
    profile
    |> required_fields()
    |> Enum.flat_map(fn
      {:one_of, fields} ->
        fields = if vat_registered?(identity), do: fields, else: fields -- [:vat_number]

        if Enum.any?(fields, &present?(identity, &1)),
          do: [],
          else: [fields |> Enum.map_join("_or_", &Atom.to_string/1) |> String.to_atom()]

      field ->
        if present?(identity, field), do: [], else: [field]
    end)
  end

  @doc "True when the business charges VAT on its sales."
  def vat_registered?(identity), do: Map.get(identity, :vat_scheme, "standard") == "standard"

  defp present?(identity, field) do
    case Map.get(identity, field) do
      nil -> false
      value when is_binary(value) -> String.trim(value) != ""
      _value -> true
    end
  end

  @doc "Serialisable view of a profile for the API."
  def public(%{country: country} = profile) do
    %{
      country: country,
      currency: profile.currency,
      languages: profile.languages,
      tax_system: Atom.to_string(profile.tax_system),
      authority: Atom.to_string(profile.authority),
      register: Atom.to_string(profile.register),
      till_device: Atom.to_string(profile.till_device),
      einvoicing: Enum.map(profile.einvoicing, &Atom.to_string/1),
      required_fields:
        profile
        |> required_fields()
        |> Enum.map(fn
          {:one_of, fields} -> Enum.map_join(fields, "_or_", &Atom.to_string/1)
          field -> Atom.to_string(field)
        end),
      tax_office: profile.tax_office,
      retention_years: profile.retention_years
    }
  end
end
