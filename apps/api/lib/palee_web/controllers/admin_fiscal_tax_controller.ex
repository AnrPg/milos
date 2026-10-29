defmodule PaleeWeb.AdminFiscalTaxController do
  @moduledoc """
  Staff › Fiscal › taxes, document files and accounting exports
  (ADR-244, ADR-245): the tax categories the gym may use, its US sales tax
  rates, a fiscal document as PDF or printable HTML, and the exports of a
  period for DATEV, Xero, QuickBooks Online, Sage, bexio or as plain CSV
  and JSON.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Fiscal.{FiscalDocumentRendering, FiscalTaxSettings}
  alias PaleeWeb.Schemas.Fiscal, as: F
  alias PaleeWeb.Schemas.FiscalTax, as: T

  action_fallback PaleeWeb.FallbackController

  tags(["Fiscal"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: F.uuid()}
  @date %Schema{type: :string, format: :date}
  @language %Parameter{
    name: :language,
    in: :query,
    required: false,
    description: "Render in this language instead of the document's own",
    schema: %Schema{type: :string, enum: ~w(el en de fr it nl es)}
  }
  @format %Parameter{
    name: :format,
    in: :path,
    required: true,
    schema: %Schema{type: :string, pattern: "^[a-z0-9_]{1,30}$"}
  }

  operation(:tax_categories,
    summary: "Tax categories the gym may give packages and products, and the default one",
    responses: [ok: {"Tax categories", "application/json", T.tax_categories()}]
  )

  def tax_categories(conn, _params),
    do: json(conn, FiscalTaxSettings.categories(conn.assigns.tenant_context))

  operation(:sales_tax_rates,
    summary: "The gym's US sales tax rates by state and ZIP code",
    responses: [ok: {"Sales tax rates", "application/json", T.sales_tax_rates()}]
  )

  def sales_tax_rates(conn, _params),
    do: json(conn, FiscalTaxSettings.sales_tax_rates(conn.assigns.tenant_context))

  operation(:save_sales_tax_rates,
    summary: "Replace the gym's US sales tax rates (journaled)",
    description:
      "Only for a business whose legal identity is in the US (`sales_tax_not_applicable` " <>
        "otherwise). A ZIP code rate wins over its state's rate.",
    request_body: F.body(T.sales_tax_rates_body()),
    responses: [ok: {"Sales tax rates", "application/json", T.sales_tax_rates()}]
  )

  def save_sales_tax_rates(conn, _params) do
    with {:ok, rates} <-
           FiscalTaxSettings.save_sales_tax_rates(conn.assigns.tenant_context, conn.body_params) do
      json(conn, rates)
    end
  end

  operation(:document_pdf,
    summary: "A fiscal document as PDF, with its country's mentions (and the Swiss QR-bill)",
    parameters: [@id, @language],
    responses: [ok: {"PDF", "application/pdf", %Schema{type: :string, format: :binary}}]
  )

  def document_pdf(conn, %{id: id} = params), do: document_file(conn, id, :pdf, params)

  operation(:document_html,
    summary: "A fiscal document as printable HTML",
    parameters: [@id, @language],
    responses: [ok: {"HTML", "text/html", %Schema{type: :string}}]
  )

  def document_html(conn, %{id: id} = params), do: document_file(conn, id, :html, params)

  defp document_file(conn, id, format, params) do
    with {:ok, %{content: content, content_type: content_type, filename: filename}} <-
           FiscalDocumentRendering.call(
             conn.assigns.tenant_context,
             id,
             format,
             Map.get(params, :language)
           ) do
      send_download(conn, {:binary, content},
        filename: filename,
        content_type: content_type,
        disposition: if(format == :pdf, do: :attachment, else: :inline)
      )
    end
  end

  operation(:export_formats,
    summary: "Accounting export formats and the gym's options for each",
    responses: [ok: {"Formats", "application/json", T.export_formats()}]
  )

  def export_formats(conn, _params),
    do: json(conn, FiscalTaxSettings.export_formats(conn.assigns.tenant_context))

  operation(:save_export_settings,
    summary: "Save the gym's options of an accounting export format (journaled)",
    description:
      "Unknown options are dropped and missing ones take their default; invalid ones come " <>
        "back as `validation_failed` with `options.<key>` fields.",
    parameters: [@format],
    request_body: F.body(T.export_settings_body()),
    responses: [ok: {"Setting", "application/json", F.one(:setting, T.export_setting())}]
  )

  def save_export_settings(conn, %{format: format}) do
    with {:ok, setting} <-
           FiscalTaxSettings.save_export_settings(
             conn.assigns.tenant_context,
             format,
             conn.body_params
           ) do
      json(conn, %{setting: setting})
    end
  end

  operation(:export,
    summary: "Download the accounting export of a period (at most 366 days)",
    description:
      "Fiscal documents issued in the period (credit notes negative) and Finance payments, " <>
        "in the format's file layout, with the gym's saved options. The export is journaled. " <>
        "`x-palee-export-skipped` counts documents or payments the format cannot carry.",
    parameters: [
      @format,
      %Parameter{name: :from, in: :query, required: true, schema: @date},
      %Parameter{name: :to, in: :query, required: true, schema: @date}
    ],
    responses: [
      ok: {"Export file", "application/octet-stream", %Schema{type: :string, format: :binary}}
    ]
  )

  def export(conn, %{format: format} = params) do
    with {:ok, export} <-
           FiscalTaxSettings.export(conn.assigns.tenant_context, format, params) do
      conn
      |> put_resp_header("x-palee-export-documents", Integer.to_string(export.documents))
      |> put_resp_header("x-palee-export-payments", Integer.to_string(export.payments))
      |> put_resp_header("x-palee-export-skipped", Integer.to_string(export.skipped))
      |> send_download({:binary, export.content},
        filename: export.filename,
        content_type: export.content_type
      )
    end
  end
end
