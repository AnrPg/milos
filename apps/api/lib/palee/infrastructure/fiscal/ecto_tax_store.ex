defmodule Palee.Infrastructure.Fiscal.EctoTaxStore do
  @moduledoc "Ecto adapter of the Fiscal tax and export settings store (ADR-244, ADR-245)."

  @behaviour Palee.Fiscal.Ports.TaxStore

  import Ecto.Query

  alias Palee.Fiscal.{DocumentLine, ExportSetting, SalesTaxRate}
  alias Palee.Repo

  @impl true
  def transaction(_context, fun) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # ── Sales tax rates ───────────────────────────────────────────────────────

  @impl true
  def list_sales_tax_rates(%{organization_id: organization_id}) do
    SalesTaxRate
    |> where([r], r.organization_id == ^organization_id)
    |> order_by([r], asc: r.state, asc_nulls_first: r.zip)
    |> Repo.all()
    |> Enum.map(&rate_map/1)
  end

  @impl true
  def replace_sales_tax_rates(%{organization_id: organization_id} = context, rates, actor_id) do
    Repo.transaction(fn ->
      SalesTaxRate |> where([r], r.organization_id == ^organization_id) |> Repo.delete_all()

      Enum.each(rates, fn rate ->
        case rate |> Map.put(:updated_by_id, actor_id) |> SalesTaxRate.changeset() |> Repo.insert() do
          {:ok, _row} -> :ok
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

      list_sales_tax_rates(context)
    end)
  end

  defp rate_map(%SalesTaxRate{} = rate),
    do: Map.take(rate, [:id, :state, :zip, :rate_bp, :label, :updated_at])

  # ── Export settings ───────────────────────────────────────────────────────

  @impl true
  def list_export_settings(%{organization_id: organization_id}) do
    ExportSetting
    |> where([s], s.organization_id == ^organization_id)
    |> order_by([s], asc: s.format)
    |> Repo.all()
    |> Enum.map(&setting_map/1)
  end

  @impl true
  def get_export_setting(%{organization_id: organization_id}, format) do
    ExportSetting
    |> where([s], s.organization_id == ^organization_id and s.format == ^format)
    |> Repo.one()
    |> setting_map()
  end

  @impl true
  def save_export_setting(%{organization_id: organization_id}, format, options, actor_id) do
    case Repo.one(
           from s in ExportSetting,
             where: s.organization_id == ^organization_id and s.format == ^format
         ) do
      nil -> %ExportSetting{organization_id: organization_id}
      setting -> setting
    end
    |> ExportSetting.changeset(%{format: format, options: options, updated_by_id: actor_id})
    |> Repo.insert_or_update()
    |> case do
      {:ok, setting} -> {:ok, setting_map(setting)}
      error -> error
    end
  end

  defp setting_map(nil), do: nil

  defp setting_map(%ExportSetting{} = setting),
    do: Map.take(setting, [:format, :options, :updated_at])

  # ── Document lines ────────────────────────────────────────────────────────

  @impl true
  def lines_for_documents(_context, []), do: %{}

  def lines_for_documents(%{organization_id: organization_id}, ids) do
    DocumentLine
    |> where([l], l.organization_id == ^organization_id and l.document_id in ^ids)
    |> order_by([l], asc: l.document_id, asc: l.position)
    |> Repo.all()
    |> Enum.map(&(&1 |> Map.from_struct() |> Map.drop([:__meta__])))
    |> Enum.group_by(& &1.document_id)
  end
end
