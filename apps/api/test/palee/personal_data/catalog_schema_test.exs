defmodule Palee.PersonalData.CatalogSchemaTest do
  @moduledoc """
  ADR-267: the personal data catalog against the real schema, so a renamed
  table or column cannot silently drop data from "Download my data".
  """

  use Palee.DataCase, async: true

  import Palee.TestFixtures

  alias Palee.{Organizations, PersonalData, Repo}
  alias Palee.PersonalData.Domain.Catalog

  defp columns do
    %{rows: rows} =
      Repo.query!(
        "SELECT table_name, column_name FROM information_schema.columns WHERE table_schema = 'public'"
      )

    Enum.group_by(rows, &hd/1, &List.last/1)
  end

  defp subject_columns({:eq, column}, table), do: [{table, column}]

  defp subject_columns({:in, column, parent, parent_column, parent_subject}, table),
    do: [{table, column}, {parent, parent_column} | subject_columns(parent_subject, parent)]

  defp subject_columns({:any, subjects}, table),
    do: Enum.flat_map(subjects, &subject_columns(&1, table))

  test "every table and column the catalog names exists" do
    columns = columns()

    for entry <- Catalog.entries() do
      assert Map.has_key?(columns, entry.table), "#{entry.table} is not a table"

      for {table, column} <- subject_columns(entry.subject, entry.table) do
        assert column in Map.get(columns, table, []), "#{table}.#{column} does not exist"
      end

      for column <- entry.drop do
        assert column in columns[entry.table], "#{entry.table}.#{column} (drop) does not exist"
      end

      if entry.scope == :tenant do
        assert "organization_id" in columns[entry.table],
               "#{entry.table} is read per business but has no organization_id"
      end
    end
  end

  test "account entries are tables a person's own session can read" do
    %{rows: rows} =
      Repo.query!("""
      SELECT c.relname, c.relrowsecurity,
             EXISTS (SELECT 1 FROM pg_policies p
                     WHERE p.tablename = c.relname
                       AND (p.qual ILIKE '%app.user_id%' OR p.cmd = 'ALL' AND p.qual ILIKE '%user_id%'))
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind = 'r'
      """)

    security = Map.new(rows, fn [table, rls, own] -> {table, {rls, own}} end)

    for %{table: table} <- Catalog.entries(:account) do
      case security[table] do
        # Platform tables without row-level security (users, logins, login_devices).
        {false, _own} -> :ok
        {true, own} -> assert own, "#{table} has no policy for the person's own session"
      end
    end
  end

  test "every entry's query runs, for a person in a business" do
    person = user_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{name: "Box #{System.unique_integer([:positive])}"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: person.id,
        role: :member,
        roles: [:member],
        status: :active,
        joined_at: DateTime.utc_now()
      })

    sections = PersonalData.collect(person.id)

    assert Map.keys(sections) |> Enum.sort() == Enum.sort(Catalog.sections())
    assert [%{"id" => id}] = sections["profile"]["users"]
    assert id == person.id
    assert [%{"organization_id" => org_id}] = sections["profile"]["organization_memberships"]
    assert org_id == organization.id
    refute Map.has_key?(hd(sections["profile"]["logins"]), "password_hash")
  end
end
