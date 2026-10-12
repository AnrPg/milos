defmodule MilosTraining.TenantData.Domain.RetentionReview do
  @moduledoc """
  Pure helpers shared by every bounded context's tenant data policy (ADR-117).

  A context policy is a plain map:

      %{
        context: "finance",
        purge_order: 90,                       # lower purges first
        disposition: :purge | :retain | :retain_anonymized,
        retain_years: nil | pos_integer,
        basis: "why this disposition applies",
        tables: [table_spec],                  # in delete (dependency) order
        retained_tables: [table_name],         # copied into the retention archive
        anonymized_columns: [column_name],     # dropped from retained rows
        excluded_columns: [column_name],       # never exported (secrets)
        retained_object_prefixes: [prefix]     # tenant-relative, kept on cleanup
      }

  A table spec is `%{table: name}` plus optional `parent: {table, fk}` for child
  tables without `organization_id`, and `rls: :user | {:user_via, table, fk}`
  for personal tables whose row security keys on the owning user.
  """

  @dispositions [:purge, :retain, :retain_anonymized]
  @identifier ~r/^[a-z][a-z0-9_]*$/

  def dispositions, do: @dispositions

  @doc "Fills defaults and validates the policy shape. Raises on programmer error."
  def normalize!(%{context: context, purge_order: order, disposition: disposition} = policy)
      when is_binary(context) and is_integer(order) and disposition in @dispositions do
    policy =
      Map.merge(
        %{
          retain_years: nil,
          basis: "",
          tables: [],
          retained_tables: [],
          anonymized_columns: [],
          excluded_columns: [],
          retained_object_prefixes: []
        },
        policy
      )

    Enum.each(policy.tables, &validate_spec!/1)

    if disposition != :purge and not (is_integer(policy.retain_years) and policy.retain_years > 0) do
      raise ArgumentError, "#{context}: retained dispositions need a positive retain_years"
    end

    policy
  end

  def normalize!(policy),
    do: raise(ArgumentError, "invalid tenant data policy: #{inspect(policy)}")

  @doc "Orders policies so dependents are purged before the tables they reference."
  def purge_sequence(policies), do: Enum.sort_by(policies, & &1.purge_order)

  @doc "Date until which retained records must be kept."
  def retained_until(%{disposition: :purge}, _today), do: nil

  def retained_until(%{retain_years: years}, %Date{} = today) when is_integer(years),
    do: Date.shift(today, year: years)

  def retained_until(_policy, _today), do: nil

  @doc "Tables whose rows go into the retention archive."
  def retained_tables(%{disposition: :purge}), do: []

  def retained_tables(%{retained_tables: [], tables: tables}), do: Enum.map(tables, & &1.table)
  def retained_tables(%{retained_tables: retained}), do: retained

  @doc """
  One retention-review entry per context: record counts per resource, the
  disposition, and the retention deadline.
  """
  def entry(policy, inventory, %Date{} = today) when is_list(inventory) do
    retained_until = retained_until(policy, today)

    %{
      "context" => policy.context,
      "disposition" => Atom.to_string(policy.disposition),
      "retain_years" => policy.retain_years,
      "retained_until" => retained_until && Date.to_iso8601(retained_until),
      "basis" => policy.basis,
      "record_count" => Enum.reduce(inventory, 0, &(&1.count + &2)),
      "resources" =>
        Enum.map(inventory, fn %{resource: resource, count: count} ->
          %{"resource" => resource, "count" => count}
        end)
    }
  end

  @doc "Retention-review entry for global accounts touched by the purge (ADR-093)."
  def identity_entry(deletable_count, shared_count)
      when is_integer(deletable_count) and is_integer(shared_count) do
    %{
      "context" => "identity",
      "disposition" => "purge",
      "retain_years" => nil,
      "retained_until" => nil,
      "basis" =>
        "Accounts that belong only to this tenant are deleted; accounts with other memberships or vendor authority are kept.",
      "record_count" => deletable_count,
      "resources" => [
        %{"resource" => "tenant_only_accounts", "count" => deletable_count},
        %{"resource" => "shared_accounts_kept", "count" => shared_count}
      ]
    }
  end

  @doc "Retention-review entry for stored objects (documents and avatars)."
  def storage_entry(documents, avatars, retained_prefixes)
      when is_list(documents) and is_list(avatars) do
    retained = Enum.count(documents, &retained_object?(&1.key, retained_prefixes))

    %{
      "context" => "storage",
      "disposition" => "purge",
      "retain_years" => nil,
      "retained_until" => nil,
      "basis" =>
        "Tenant documents are deleted except retained archives and documents covered by a retaining context policy; avatars of deleted accounts are deleted.",
      "record_count" => length(documents) + length(avatars),
      "resources" => [
        %{"resource" => "tenant_documents", "count" => length(documents) - retained},
        %{"resource" => "retained_documents", "count" => retained},
        %{"resource" => "account_avatars", "count" => length(avatars)}
      ]
    }
  end

  @doc "Tenant-relative object path of the full export bundle."
  def export_object_path(purge_id), do: "purge/#{purge_id}/tenant-export.zip"

  @doc "Tenant-relative prefix holding everything written for one purge's export."
  def export_object_prefix(purge_id), do: "purge/#{purge_id}/"

  @doc "Tenant-relative object path of the retention archive kept after the purge."
  def retained_archive_path(purge_id), do: "retained/#{purge_id}/retention-archive.zip"

  @doc "Tenant-relative prefix of one purge's retention archive."
  def retained_archive_prefix(purge_id), do: "retained/#{purge_id}/"

  @doc "Tenant-relative prefixes that survive object cleanup."
  def retained_object_prefixes(policies) when is_list(policies) do
    policies
    |> Enum.flat_map(fn policy ->
      if policy.disposition == :purge, do: [], else: policy.retained_object_prefixes
    end)
    |> then(&["retained/" | &1])
    |> Enum.uniq()
  end

  defp retained_object?(key, prefixes) do
    relative = String.replace(key, ~r{^organizations/[^/]+/}, "")
    Enum.any?(prefixes, &String.starts_with?(relative, &1))
  end

  @doc "Drops excluded (secret) and, for anonymized retention, identifying columns."
  def strip_columns(rows, columns) when is_list(rows) and columns == [], do: rows

  def strip_columns(rows, columns) when is_list(rows) do
    Enum.map(rows, &Map.drop(&1, columns))
  end

  def valid_identifier?(name) when is_binary(name), do: Regex.match?(@identifier, name)
  def valid_identifier?(_name), do: false

  defp validate_spec!(%{table: table} = spec) do
    names =
      [table] ++
        case Map.get(spec, :parent) do
          nil -> []
          {parent, fk} -> [parent, fk]
        end ++
        case Map.get(spec, :rls, :organization) do
          :organization -> []
          :user -> []
          {:user_via, parent, fk} -> [parent, fk]
        end

    unless Enum.all?(names, &valid_identifier?/1) do
      raise ArgumentError, "invalid tenant table spec: #{inspect(spec)}"
    end
  end
end
