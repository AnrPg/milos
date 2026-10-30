defmodule Palee.Fiscal.Domain.VatRates do
  @moduledoc """
  VAT rates of the supported countries by tax category and date (ADR-241).

  Rates are basis points (2400 = 24 %, 810 = 8.1 %) so no float is ever
  stored or hashed. Each category keeps its history (`[{valid_from, bp}]`,
  newest first) so a document dated before a change uses the old rate.

  Categories:

    * `standard`, `reduced`, `second_reduced`, `super_reduced`, `special`
      (Swiss accommodation rate) – the country's rates where they exist;
    * `zero` – zero-rated supplies (0 %, still VAT-able);
    * `exempt` – exempt supplies (0 %, a reason is required: small business
      scheme, sports services exemption, …);
    * `sales_tax` – US only: the rate comes from the sales tax port
      (ADR-244), never from this table.

  Most gym services (memberships, classes, personal training) are
  `standard`; some countries tax access to sports facilities at a reduced
  rate. Which category a package uses is the gym's choice, made with its
  accountant (ADR-244 adds it to packages and products).
  """

  @categories ~w(standard reduced second_reduced super_reduced special zero exempt sales_tax)

  @eu_start ~D[2000-01-01]

  @rates %{
    "GR" => %{
      "standard" => [{~D[2016-06-01], 2400}],
      "reduced" => [{~D[2016-06-01], 1300}],
      "super_reduced" => [{~D[2016-06-01], 600}]
    },
    "CY" => %{
      "standard" => [{~D[2014-01-13], 1900}],
      "reduced" => [{~D[2014-01-13], 900}],
      "super_reduced" => [{~D[2014-01-13], 500}]
    },
    "DE" => %{
      "standard" => [{~D[2021-01-01], 1900}, {~D[2020-07-01], 1600}, {~D[2007-01-01], 1900}],
      "reduced" => [{~D[2021-01-01], 700}, {~D[2020-07-01], 500}, {~D[2007-01-01], 700}]
    },
    "AT" => %{
      "standard" => [{~D[2016-01-01], 2000}],
      "reduced" => [{~D[2016-01-01], 1300}],
      "second_reduced" => [{~D[2016-01-01], 1000}]
    },
    "CH" => %{
      "standard" => [{~D[2024-01-01], 810}, {~D[2018-01-01], 770}],
      "reduced" => [{~D[2024-01-01], 260}, {~D[2018-01-01], 250}],
      "special" => [{~D[2024-01-01], 380}, {~D[2018-01-01], 370}]
    },
    "LI" => %{
      "standard" => [{~D[2024-01-01], 810}, {~D[2018-01-01], 770}],
      "reduced" => [{~D[2024-01-01], 260}, {~D[2018-01-01], 250}],
      "special" => [{~D[2024-01-01], 380}, {~D[2018-01-01], 370}]
    },
    "LU" => %{
      "standard" => [{~D[2024-01-01], 1700}, {~D[2023-01-01], 1600}, {~D[2015-01-01], 1700}],
      "reduced" => [{~D[2024-01-01], 800}, {~D[2023-01-01], 700}, {~D[2015-01-01], 800}],
      "second_reduced" => [{~D[2024-01-01], 1400}, {~D[2023-01-01], 1300}, {~D[2015-01-01], 1400}],
      "super_reduced" => [{~D[2015-01-01], 300}]
    },
    "FR" => %{
      "standard" => [{~D[2014-01-01], 2000}],
      "reduced" => [{~D[2014-01-01], 1000}],
      "second_reduced" => [{~D[2014-01-01], 550}],
      "super_reduced" => [{~D[2014-01-01], 210}]
    },
    "MC" => %{
      "standard" => [{~D[2014-01-01], 2000}],
      "reduced" => [{~D[2014-01-01], 1000}],
      "second_reduced" => [{~D[2014-01-01], 550}],
      "super_reduced" => [{~D[2014-01-01], 210}]
    },
    "BE" => %{
      "standard" => [{~D[1996-01-01], 2100}],
      "reduced" => [{~D[1996-01-01], 1200}],
      "super_reduced" => [{~D[1996-01-01], 600}]
    },
    "GB" => %{
      "standard" => [{~D[2011-01-04], 2000}],
      "reduced" => [{~D[2011-01-04], 500}]
    },
    "US" => %{}
  }

  def categories, do: @categories

  @doc "Categories a country offers (its own rates plus `zero` and `exempt`, or `sales_tax`)."
  def categories(country) when is_map_key(@rates, country) do
    own = @rates |> Map.fetch!(country) |> Map.keys()

    if country == "US",
      do: ["sales_tax", "exempt"],
      else: Enum.filter(@categories, &(&1 in own or &1 in ["zero", "exempt"]))
  end

  def categories(_country), do: []

  @doc """
  `{:ok, basis_points}` for a category in a country on a date, or
  `{:error, :unknown_tax_category}` / `{:error, :rate_from_sales_tax_port}`.
  """
  def rate(country, category, %Date{} = on) do
    cond do
      category in ["zero", "exempt"] and is_map_key(@rates, country) ->
        {:ok, 0}

      category == "sales_tax" and country == "US" ->
        {:error, :rate_from_sales_tax_port}

      true ->
        with %{} = rates <- Map.get(@rates, country),
             [_ | _] = history <- Map.get(rates, category),
             {_from, bp} <-
               Enum.find(history, fn {from, _bp} -> Date.compare(from, on) != :gt end) do
          {:ok, bp}
        else
          _ -> {:error, :unknown_tax_category}
        end
    end
  end

  @doc "The earliest date any rate in the table is known from."
  def known_from, do: @eu_start
end
