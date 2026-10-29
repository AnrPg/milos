defmodule Palee.Infrastructure.Fiscal.Exports.GenericJson do
  @moduledoc """
  Palee's own JSON export (ADR-245): the bookkeeping entries of
  `Palee.Fiscal.Domain.ExportEntries` as they are (signed integer cents,
  ISO dates), with the period, the seller and `format`
  `palee-accounting-export` version 1.
  """

  @behaviour Palee.Fiscal.Ports.AccountingExportFormat

  alias Palee.Fiscal.Domain.ExportOptions

  @version 1

  @impl true
  def id, do: "json"

  @impl true
  def describe do
    %{
      id: id(),
      name: "JSON",
      description: "Documents with their VAT groups and lines, and payments, in signed cents.",
      file_extension: "json",
      file_prefix: "palee-accounting",
      content_type: "application/json",
      options: []
    }
  end

  @impl true
  def normalize_options(options), do: ExportOptions.normalize([], options)

  @impl true
  def render(%{entries: entries} = context, _options) do
    seller = Map.get(context, :seller, %{})

    content =
      Jason.encode!(
        %{
          format: "palee-accounting-export",
          version: @version,
          from: context.from,
          to: context.to,
          generated_at: context.generated_at,
          seller: Map.take(seller, [:legal_name, :country_code, :vat_number, :tax_id, :currency]),
          documents: entries.documents,
          payments: entries.payments
        },
        pretty: true
      )

    {:ok, %{content: content, skipped: 0}}
  end
end
