defmodule MilosTraining.TenantData.TenantTableCoverageTest do
  @moduledoc """
  ADR-117 guard: every table carrying `organization_id` must be declared by
  exactly one bounded context's tenant data policy, so a new tenant table can
  never be silently left out of the export or the purge.
  """

  use MilosTraining.DataCase, async: true

  alias MilosTraining.Application.TenantDataContexts
  alias MilosTraining.Organizations

  # Platform-level records that must survive a purge by design.
  @not_tenant_data ~w(organization_purges)

  test "every organization_id table is owned by exactly one context policy" do
    declared =
      (TenantDataContexts.policies() ++ [Organizations.tenant_data_policy()])
      |> Enum.flat_map(fn policy -> Enum.map(policy.tables, & &1.table) end)

    assert declared -- Enum.uniq(declared) == [], "tables declared twice"

    %{rows: rows} =
      Repo.query!("""
      SELECT DISTINCT c.relname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid
      WHERE n.nspname = 'public' AND c.relkind = 'r'
        AND a.attname = 'organization_id' AND NOT a.attisdropped
      """)

    tenant_tables = List.flatten(rows) -- @not_tenant_data

    assert tenant_tables -- declared == [], "undeclared tenant tables"
  end
end
