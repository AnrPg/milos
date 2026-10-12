defmodule MilosTraining.Infrastructure.TenantData.EctoTableStore do
  @moduledoc """
  Ecto adapter executing context-declared tenant table specs (ADR-099).

  Deletes use Ecto `delete_all` (no raw SQL mutation). Exports reuse the same
  Ecto predicate for the id set and wrap it in `row_to_json` so every column is
  captured with Postgres' own JSON encoding, without a schema per table.
  Table and column names only ever come from compile-time context policies and
  are re-validated as plain identifiers before use.
  """

  @behaviour MilosTraining.TenantData.Ports.TableStore

  import Ecto.Query

  alias MilosTraining.Repo
  alias MilosTraining.TenantData.Domain.RetentionReview

  @impl true
  def count(spec, organization_id, user_id) do
    spec
    |> scoped_query(organization_id, user_id)
    |> select([row], count())
    |> Repo.one()
  end

  @impl true
  def export(spec, organization_id, user_id) do
    table = identifier!(spec.table)

    {id_sql, params} =
      Ecto.Adapters.SQL.to_sql(
        :all,
        Repo,
        spec |> scoped_query(organization_id, user_id) |> select([row], field(row, :id))
      )

    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Repo,
        ~s|SELECT row_to_json(export_row) FROM "#{table}" AS export_row | <>
          ~s|WHERE export_row.id IN (#{id_sql}) ORDER BY export_row.id|,
        params
      )

    Enum.map(rows, fn [row] -> row end)
  end

  @impl true
  def delete(spec, organization_id, user_id) do
    {deleted, _rows} =
      spec
      |> scoped_query(organization_id, user_id)
      |> Repo.delete_all()

    deleted
  end

  @impl true
  def transaction(fun) when is_function(fun, 0) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp scoped_query(spec, organization_id, user_id) do
    spec.table
    |> identifier!()
    |> from()
    |> tenant_predicate(Map.get(spec, :parent), organization_id)
    |> owner_predicate(Map.get(spec, :rls, :organization), user_id)
  end

  defp tenant_predicate(query, nil, organization_id) do
    where(query, [row], field(row, :organization_id) == type(^organization_id, :binary_id))
  end

  defp tenant_predicate(query, {parent, fk}, organization_id) do
    parent_ids =
      parent
      |> identifier!()
      |> from()
      |> where([parent], field(parent, :organization_id) == type(^organization_id, :binary_id))
      |> select([parent], field(parent, :id))

    # Safe: identifiers come from compile-time context policies and are validated.
    fk = String.to_atom(identifier!(fk))
    where(query, [row], field(row, ^fk) in subquery(parent_ids))
  end

  defp owner_predicate(query, :organization, _user_id), do: query

  defp owner_predicate(query, :user, user_id) when is_binary(user_id) do
    where(query, [row], field(row, :user_id) == type(^user_id, :binary_id))
  end

  defp owner_predicate(query, {:user_via, parent, fk}, user_id) when is_binary(user_id) do
    owned_ids =
      parent
      |> identifier!()
      |> from()
      |> where([parent], field(parent, :user_id) == type(^user_id, :binary_id))
      |> select([parent], field(parent, :id))

    # Safe: identifiers come from compile-time context policies and are validated.
    fk = String.to_atom(identifier!(fk))
    where(query, [row], field(row, ^fk) in subquery(owned_ids))
  end

  defp identifier!(name) do
    if RetentionReview.valid_identifier?(name),
      do: name,
      else: raise(ArgumentError, "invalid tenant table identifier: #{inspect(name)}")
  end
end
