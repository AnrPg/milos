defmodule Palee.Imports.ImportStore do
  @moduledoc false
  @behaviour Palee.Imports.Ports.ImportStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :import_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def transaction(context, fun), do: tenant_call(context, :transaction, [fun])

  @impl true
  def insert_import(context, attrs, rows), do: tenant_call(context, :insert_import, [attrs, rows])
  @impl true
  def get_import(context, id, opts \\ []), do: tenant_call(context, :get_import, [id, opts])
  @impl true
  def list_imports(context, filters), do: tenant_call(context, :list_imports, [filters])
  @impl true
  def update_import(context, id, changes), do: tenant_call(context, :update_import, [id, changes])
  @impl true
  def delete_import(context, id), do: tenant_call(context, :delete_import, [id])

  @impl true
  def list_rows(context, import_id, filters),
    do: tenant_call(context, :list_rows, [import_id, filters])

  @impl true
  def save_plans(context, import_id, plans),
    do: tenant_call(context, :save_plans, [import_id, plans])

  @impl true
  def lock_row(context, id), do: tenant_call(context, :lock_row, [id])
  @impl true
  def update_row(context, id, changes), do: tenant_call(context, :update_row, [id, changes])

  @impl true
  def applied_fingerprints(context, fingerprints),
    do: tenant_call(context, :applied_fingerprints, [fingerprints])

  @impl true
  def row_counts(context, import_id), do: tenant_call(context, :row_counts, [import_id])

  @impl true
  def list_people(context), do: tenant_call(context, :list_people, [])
  @impl true
  def find_person(context, key, value), do: tenant_call(context, :find_person, [key, value])
  @impl true
  def upsert_person(context, attrs), do: tenant_call(context, :upsert_person, [attrs])
  @impl true
  def update_person(context, id, changes), do: tenant_call(context, :update_person, [id, changes])
  @impl true
  def people_of_import(context, import_id),
    do: tenant_call(context, :people_of_import, [import_id])
end
