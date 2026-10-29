defmodule Palee.Fiscal.Ports.AccountingExportFormat do
  @moduledoc """
  An accounting export format (ADR-245): turns the neutral bookkeeping
  entries of a period (`Palee.Fiscal.Domain.ExportEntries`) into the file
  an accounting package imports. Adapters live in
  `Palee.Infrastructure.Fiscal.Exports` and are listed in
  `config :palee, :fiscal_accounting_export_formats`.

  Adapters are pure: no database, no clock (the generation time comes in
  the render context).
  """

  @typedoc """
  An option a gym can set for a format:
  `%{key, type, default, description}` with `type` one of `"string"`,
  `"integer"`, `"boolean"`, `"enum"` (with `values`) or `"map"` (text keys
  to text values, e.g. tax category → account).
  """
  @type option :: map()

  @typedoc "`%{id, name, description, file_extension, content_type, options: [option]}`"
  @type description :: map()

  @typedoc """
  `%{entries: %{documents, payments}, from: Date, to: Date, generated_at:
  DateTime, seller: %{legal_name, country_code, currency, vat_number}}`
  """
  @type render_context :: map()

  @doc "Stable identifier used in URLs and settings (`datev`, `xero`, ...)."
  @callback id() :: String.t()

  @callback describe() :: description()

  @doc """
  Validates options (string or atom keys) and fills defaults:
  `{:ok, options}` with string keys, or
  `{:error, {:invalid_fields, %{"options.key" => reason}}}`.
  """
  @callback normalize_options(map()) :: {:ok, map()} | {:error, term()}

  @doc """
  `{:ok, %{content, skipped}}`: the file and how many documents or payments
  the format cannot carry (e.g. credit notes in QuickBooks invoice import).
  """
  @callback render(render_context(), options :: map()) ::
              {:ok, %{content: binary(), skipped: non_neg_integer()}} | {:error, term()}
end
