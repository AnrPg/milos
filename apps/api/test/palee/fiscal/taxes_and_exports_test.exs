defmodule Palee.FiscalTaxesAndExportsTest do
  @moduledoc """
  ADR-244/245 through the Fiscal context and the database, with Row Level
  Security enforced: bank details on the identity, US sales tax rates,
  rendering an issued document, export settings and accounting exports,
  all journaled.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.AnalyticsHelpers, only: [organization_fixture: 0]

  alias Palee.Application.Fiscal.{FiscalDocumentRendering, FiscalTaxSettings}
  alias Palee.Fiscal
  alias Palee.Fiscal.{Exports, FiscalStore, Taxes}

  @now ~U[2027-02-03 10:00:00.000000Z]

  @swiss %{
    legal_name: "CrossFit Zürich AG",
    country_code: "CH",
    street: "Bahnhofstrasse",
    building_number: "10",
    postal_code: "8001",
    city: "Zürich",
    iban: "CH56 0483 5012 3456 7800 9",
    qr_iban: "CH44 3199 9123 0008 8901 2"
  }

  @american %{
    legal_name: "Brooklyn Barbell LLC",
    country_code: "US",
    street: "Atlantic Ave",
    building_number: "100",
    postal_code: "11201",
    city: "Brooklyn",
    region: "NY",
    # A Swiss QR-IBAN saved earlier must be cleared when moving to the US.
    iban: nil,
    qr_iban: nil
  }

  setup do
    {organization, owner, context} = bypass_rls(fn -> organization_fixture() end)
    %{organization: organization, owner: owner, context: context}
  end

  defp journal_events(context) do
    context
    |> FiscalStore.list_journal_entries(%{after_position: 0, limit: 100})
    |> Enum.map(& &1.event_type)
  end

  test "bank details are validated on the identity", %{context: context, owner: owner} do
    assert {:error, {:invalid_fields, %{iban: :invalid_iban}}} =
             Fiscal.save_identity(context, %{@swiss | iban: "CH56 0483 5012 3456 7800 8"}, owner.id, @now)

    assert {:error, {:invalid_fields, %{iban: :qr_iban_in_iban_field}}} =
             Fiscal.save_identity(context, %{@swiss | iban: @swiss.qr_iban}, owner.id, @now)

    assert {:error, {:invalid_fields, %{qr_iban: :not_a_qr_iban}}} =
             Fiscal.save_identity(context, %{@swiss | qr_iban: @swiss.iban}, owner.id, @now)

    assert {:ok, %{complete: true, identity: identity}} =
             Fiscal.save_identity(context, @swiss, owner.id, @now)

    assert identity.iban == "CH5604835012345678009"
    assert identity.qr_iban == "CH4431999123000889012"
  end

  test "US sales tax rates are kept per state and ZIP and used for sales tax lines", %{
    context: context,
    owner: owner
  } do
    assert {:error, :fiscal_identity_missing} = Taxes.rate(context, "sales_tax", ~D[2027-02-03])

    {:ok, _status} = Fiscal.save_identity(context, @swiss, owner.id, @now)

    assert {:error, :sales_tax_not_applicable} =
             Taxes.save_sales_tax_rates(context, [%{state: "NY", rate_bp: 400}], owner.id, @now)

    {:ok, _status} = Fiscal.save_identity(context, @american, owner.id, @now)
    assert %{applies: true, rates: []} = Taxes.sales_tax_rates(context)

    assert {:error, {:invalid_fields, %{"rates.0.state" => :invalid}}} =
             Taxes.save_sales_tax_rates(context, [%{state: "XX", rate_bp: 1}], owner.id, @now)

    assert {:ok, %{rates: [%{state: "NY", zip: nil, rate_bp: 400}, %{zip: "11201", rate_bp: 887}]}} =
             Taxes.save_sales_tax_rates(
               context,
               [%{"state" => "NY", "rate_bp" => 400}, %{"state" => "NY", "zip" => "11201", "rate_bp" => 887}],
               owner.id,
               @now
             )

    assert {:ok, 887} = Taxes.rate(context, "sales_tax", ~D[2027-02-03])
    assert {:ok, 400} = Taxes.rate(context, "sales_tax", ~D[2027-02-03], %{region: "NY", postal_code: "12207"})

    assert {:error, :sales_tax_rate_missing} =
             Taxes.rate(context, "sales_tax", ~D[2027-02-03], %{region: "CA", postal_code: "90001"})

    assert {:ok, [%{rate_bp: 887}, %{tax_category: "exempt", rate_bp: nil}]} =
             Taxes.apply_sales_tax(
               context,
               [
                 %{description: "Membership", unit_price_cents: 9_900, tax_category: "sales_tax"},
                 %{description: "Gift card", unit_price_cents: 5_000, tax_category: "exempt", rate_bp: nil}
               ],
               ~D[2027-02-03]
             )

    # The new table is issued against like any VAT country.
    {:ok, document, :issued} =
      Fiscal.issue(
        context,
        %{
          kind: "receipt",
          issue_date: ~D[2027-02-03],
          idempotency_key: "us-1",
          payment_method: "card",
          lines: [
            %{
              description: "Membership",
              quantity: 1,
              unit_price_cents: 10_887,
              tax_category: "sales_tax",
              rate_bp: 887
            }
          ]
        },
        owner.id,
        @now
      )

    assert document.tax_cents == 887

    assert %{categories: ["sales_tax", "exempt"], default: "sales_tax"} =
             FiscalTaxSettings.categories(context)
  end

  describe "with a Swiss invoice" do
    setup %{context: context, owner: owner} do
      {:ok, _status} = Fiscal.save_identity(context, @swiss, owner.id, @now)

      {:ok, invoice, :issued} =
        Fiscal.issue(
          context,
          %{
            kind: "invoice",
            issue_date: ~D[2027-02-03],
            idempotency_key: "ch-1",
            buyer: %{
              name: "Muster Treuhand GmbH",
              street: "Seestrasse",
              building_number: "5",
              postal_code: "8002",
              city: "Zürich",
              country_code: "CH"
            },
            lines: [
              %{description: "Unlimited Februar", quantity: 1, unit_price_cents: 20_000},
              %{description: "Shake", quantity: 2, unit_price_cents: 500, tax_category: "reduced"}
            ]
          },
          owner.id,
          @now
        )

      %{invoice: invoice}
    end

    test "renders as PDF and HTML in the document's language or another", %{
      context: context,
      invoice: invoice
    } do
      assert {:ok, %{content: "%PDF-" <> _rest, content_type: "application/pdf", filename: filename}} =
               FiscalDocumentRendering.call(context, invoice.id, :pdf)

      assert filename == "#{invoice.number}.pdf"

      assert {:ok, %{content: html}} = FiscalDocumentRendering.call(context, invoice.id, :html, "fr")
      assert html =~ "Section paiement"
      assert html =~ "CH44 3199 9123 0008 8901 2"
      assert html =~ "Facture"

      assert {:error, :unsupported_language} =
               FiscalDocumentRendering.call(context, invoice.id, :pdf, "pt")

      assert {:error, :not_found} =
               FiscalDocumentRendering.call(context, Ecto.UUID.generate(), :pdf)
    end

    test "export settings are validated, saved per format and journaled; exports too", %{
      context: context,
      owner: owner,
      invoice: invoice
    } do
      assert {:error, :unknown_export_format} =
               Exports.save_settings(context, "lexware", %{}, owner.id, @now)

      assert {:error, {:invalid_fields, %{"options.chart" => :invalid}}} =
               Exports.save_settings(context, "datev", %{"chart" => "SKR99"}, owner.id, @now)

      assert {:ok, %{format: "bexio", saved: true, options: %{"revenue_account" => "3200"}}} =
               Exports.save_settings(context, "bexio", %{"revenue_account" => "3200"}, owner.id, @now)

      settings = Exports.settings(context)
      assert length(settings) == 7
      assert %{saved: false} = Enum.find(settings, &(&1.format == "xero"))

      {:ok, credit, :issued} =
        Fiscal.credit(
          context,
          invoice.id,
          [%{position: 2, quantity: 1}],
          ~D[2027-02-04],
          "ch-credit",
          owner.id,
          @now
        )

      assert {:ok, export} =
               Exports.export(context, "bexio", ~D[2027-02-01], ~D[2027-02-28], %{}, [], owner.id, @now)

      assert export.filename == "bexio-buchungen_2027-02-01_2027-02-28.csv"
      assert export.documents == 2
      [_header | rows] = String.split(export.content, "\r\n", trim: true)
      assert Enum.any?(rows, &(&1 =~ "#{invoice.number};" and &1 =~ ";1100;3200;"))
      assert Enum.any?(rows, &(&1 =~ "#{credit.number};" and &1 =~ ";3200;1100;"))
      assert Enum.any?(rows, &(&1 =~ "UN81"))

      # An export overriding saved options for once.
      assert {:ok, %{content: json}} =
               Exports.export(context, "json", ~D[2027-02-01], ~D[2027-02-28], nil, [], owner.id, @now)

      assert %{"documents" => [_invoice, %{"corrects_number" => number}]} = Jason.decode!(json)
      assert number == invoice.number

      events = journal_events(context)
      assert "export_settings_saved" in events
      assert "accounting_exported" in events
      assert Fiscal.verify_journal(context, owner.id, @now) |> elem(0) == :ok
    end

    test "the use case exports Finance payments of the period too", %{context: context} do
      assert {:ok, %{content: csv, payments: 0, documents: 1}} =
               FiscalTaxSettings.export(context, "csv", %{"from" => "2027-02-01", "to" => "2027-02-28"})

      assert csv =~ "line,"

      assert {:error, :invalid_date_range} =
               FiscalTaxSettings.export(context, "csv", %{"from" => "2027-02-01", "to" => "2028-02-28"})

      assert {:error, :unknown_export_format} =
               FiscalTaxSettings.export(context, "nope", %{"from" => "2027-02-01", "to" => "2027-02-28"})
    end
  end
end
