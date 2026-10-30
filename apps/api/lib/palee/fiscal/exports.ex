defmodule Palee.Fiscal.Exports do
  @moduledoc """
  Accounting exports of the Fiscal context (ADR-245): the fiscal documents
  of a period (and, when the caller passes them, Finance payments) as the
  file an accounting package imports, through the
  `Fiscal.Ports.AccountingExportFormat` adapters configured in
  `config :palee, :fiscal_accounting_export_formats`.

  Each gym keeps its options per format (accounts, tax codes, DATEV
  numbers); a single export may override them. Saving options and every
  export are journaled (ADR-241). An export is generated synchronously,
  like the audit archive; it never changes a document.
  """

  alias Palee.Fiscal
  alias Palee.Fiscal.{FiscalStore, TaxStore}
  alias Palee.Fiscal.Domain.{CountryProfile, ExportEntries}

  @doc "The configured format modules."
  def modules, do: Application.fetch_env!(:palee, :fiscal_accounting_export_formats)

  @doc "Every format's description (`AccountingExportFormat.describe/0`)."
  def formats, do: Enum.map(modules(), & &1.describe())

  @doc "`{:ok, module}` of format `id`, or `{:error, :unknown_export_format}`."
  def format(id) do
    case Enum.find(modules(), &(&1.id() == id)) do
      nil -> {:error, :unknown_export_format}
      module -> {:ok, module}
    end
  end

  @doc """
  Each format with the gym's options (defaults filled in):
  `[%{format, name, options, saved, updated_at}]`.
  """
  def settings(context) do
    saved = context |> TaxStore.list_export_settings() |> Map.new(&{&1.format, &1})

    Enum.map(modules(), fn module ->
      setting = Map.get(saved, module.id())
      {:ok, options} = module.normalize_options((setting && setting.options) || %{})

      %{
        format: module.id(),
        name: module.describe().name,
        options: options,
        saved: setting != nil,
        updated_at: setting && setting.updated_at
      }
    end)
  end

  @doc "The gym's options of one format. `{:ok, options}` or `{:error, reason}`."
  def options(context, id) do
    with {:ok, module} <- format(id) do
      setting = TaxStore.get_export_setting(context, id)
      module.normalize_options((setting && setting.options) || %{})
    end
  end

  @doc """
  Saves the gym's options of format `id` (validated, journaled).
  `{:ok, setting}` as in `settings/1`, or `{:error, reason}`.
  """
  def save_settings(context, id, options, actor_id, %DateTime{} = now) do
    with {:ok, module} <- format(id),
         {:ok, options} <- module.normalize_options(options),
         {:ok, _saved} <-
           FiscalStore.transaction(context, fn ->
             with {:ok, saved} <- TaxStore.save_export_setting(context, id, options, actor_id),
                  {:ok, _entry} <-
                    Fiscal.append(context, %{
                      event_type: "export_settings_saved",
                      subject_type: "accounting_export_format",
                      actor_id: actor_id,
                      occurred_at: now,
                      payload: %{format: id, options: options}
                    }) do
               {:ok, saved}
             end
           end) do
      {:ok, Enum.find(settings(context), &(&1.format == id))}
    end
  end

  @doc """
  The export of `from`..`to` (issue dates, inclusive) in format `id`.
  `overrides` are options for this export only; `payments` are Finance
  payment rows (ADR-126 `payments` dataset) the caller read for the same
  period, or `[]`.

  `{:ok, %{filename, content, content_type, documents, payments, skipped}}`
  or `{:error, reason}`. Journaled as `accounting_exported` with the
  file's SHA-256.
  """
  def export(context, id, %Date{} = from, %Date{} = to, overrides, payments, actor_id, now) do
    with {:ok, module} <- format(id),
         {:ok, saved} <- options(context, id),
         {:ok, options} <- module.normalize_options(Map.merge(saved, stringify(overrides))) do
      documents = FiscalStore.documents_between(context, from, to)
      lines = TaxStore.lines_for_documents(context, Enum.map(documents, & &1.id))

      entries =
        ExportEntries.build(documents, lines, payments, outside_numbers(context, documents))

      render_context = %{
        entries: entries,
        from: from,
        to: to,
        generated_at: now,
        seller: seller(context)
      }

      with {:ok, %{content: content, skipped: skipped}} <- module.render(render_context, options),
           {:ok, _entry} <- journal(context, id, from, to, content, entries, actor_id, now) do
        description = module.describe()

        {:ok,
         %{
           filename:
             "#{description.file_prefix}_#{Date.to_iso8601(from)}_#{Date.to_iso8601(to)}.#{description.file_extension}",
           content: content,
           content_type: description.content_type,
           documents: length(entries.documents),
           payments: length(entries.payments),
           skipped: skipped
         }}
      end
    end
  end

  defp journal(context, id, from, to, content, entries, actor_id, now) do
    FiscalStore.transaction(context, fn ->
      Fiscal.append(context, %{
        event_type: "accounting_exported",
        subject_type: "accounting_export",
        actor_id: actor_id,
        occurred_at: now,
        payload: %{
          format: id,
          from: from,
          to: to,
          documents: length(entries.documents),
          payments: length(entries.payments),
          sha256: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
        }
      })
    end)
  end

  # Numbers of corrected documents issued before the period.
  defp outside_numbers(context, documents) do
    inside = MapSet.new(documents, & &1.id)

    documents
    |> Enum.map(& &1.corrects_document_id)
    |> Enum.reject(&(is_nil(&1) or MapSet.member?(inside, &1)))
    |> Enum.uniq()
    |> Map.new(fn id -> {id, context |> Fiscal.get_document(id) |> then(&(&1 && &1.number))} end)
  end

  defp seller(context) do
    case FiscalStore.get_identity(context) do
      nil ->
        %{}

      identity ->
        currency =
          case CountryProfile.fetch(identity.country_code) do
            {:ok, profile} -> profile.currency
            _ -> nil
          end

        identity
        |> Map.take([
          :legal_name,
          :country_code,
          :vat_number,
          :tax_id,
          :vat_scheme,
          :fiscal_year_start_month
        ])
        |> Map.put(:currency, currency)
    end
  end

  defp stringify(nil), do: %{}

  defp stringify(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
end
