defmodule Palee.PersonalData do
  @moduledoc """
  ADR-267: a person's own data, gathered for "Download my data" (GDPR
  articles 15 and 20). Owns the export requests and the catalog of where the
  person's data lives; reads every other context's rows only through the
  person's own sessions (`RecordSource`), so row-level security decides what
  is visible.
  """

  alias Palee.PersonalData.{ExportStore, RecordSource}
  alias Palee.PersonalData.Domain.{Archive, Catalog, ExportPolicy}

  # -- requests ------------------------------------------------------------------

  defdelegate list_exports(user_id), to: ExportStore, as: :list
  defdelegate get_export(id, user_id), to: ExportStore, as: :get
  defdelegate insert_export(attrs), to: ExportStore, as: :insert
  defdelegate finish_export(export, attrs), to: ExportStore, as: :finish

  defdelegate can_request?(exports, now), to: ExportPolicy
  defdelegate visible_status(export, now), to: ExportPolicy
  defdelegate downloadable?(export, now), to: ExportPolicy
  defdelegate expires_at(now), to: ExportPolicy
  defdelegate keep_days(), to: ExportPolicy

  # -- gathering -----------------------------------------------------------------

  @doc """
  Every catalog section with the person's rows, `%{section => %{table =>
  [row]}}`: account entries once, business entries once per business the
  person belongs or belonged to, their rows put together.
  """
  def collect(user_id) when is_binary(user_id) do
    organization_ids = RecordSource.organization_ids(user_id)

    account =
      Enum.map(Catalog.entries(:account), fn entry ->
        {entry, RecordSource.rows(entry, user_id, nil)}
      end)

    tenant =
      Enum.map(Catalog.entries(:tenant), fn entry ->
        {entry, Enum.flat_map(organization_ids, &RecordSource.rows(entry, user_id, &1))}
      end)

    Enum.reduce(account ++ tenant, %{}, fn {entry, rows}, sections ->
      Map.update(sections, entry.section, %{entry.table => rows}, &Map.put(&1, entry.table, rows))
    end)
  end

  @doc "The archive of `collect/1`'s sections (see `Archive.build/1`)."
  def archive(user_id, sections, %DateTime{} = generated_at),
    do: Archive.build(%{profile_id: user_id, generated_at: generated_at, sections: sections})

  defdelegate file_name(generated_at), to: Archive
end
