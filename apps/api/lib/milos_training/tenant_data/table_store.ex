defmodule MilosTraining.TenantData.TableStore do
  @moduledoc """
  Tenant-scoped facade over the configured `TableStore` adapter (ADR-107).

  Bounded contexts call this only with their *own* policy (declared in their
  `Domain.TenantDataPolicy`), so no context names another context's tables.
  Every adapter call runs inside `RepoContext.run/2`:

  * tenant tables under `%{organization_id, user_id: vendor}`;
  * personal tables (`rls: :user | {:user_via, ...}`) once per subject account
    under `%{organization_id, user_id: subject}`, because their policies only
    admit the owning user.

  Anything other than a `%PurgeContext{}` fails closed with
  `{:error, :organization_context_required}` (ADR-091).
  """

  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.TenantData.Domain.RetentionReview
  alias MilosTraining.TenantData.PurgeContext

  @doc "Record counts per declared table."
  def inventory(policy, %PurgeContext{organization_id: organization_id} = context)
      when is_binary(organization_id) do
    tenant_session(context, fn ->
      {:ok,
       Enum.map(policy.tables, fn spec ->
         %{resource: spec.table, count: per_scope(spec, context, &adapter().count/3, &+/2, 0)}
       end)}
    end)
  end

  def inventory(_policy, _context), do: {:error, :organization_context_required}

  @doc """
  Rows per declared table. `:full` exports everything except secret columns;
  `:retained` exports only the policy's retained tables, additionally dropping
  anonymized columns for `:retain_anonymized` policies.
  """
  def export(policy, context, mode \\ :full)

  def export(policy, %PurgeContext{organization_id: organization_id} = context, mode)
      when is_binary(organization_id) and mode in [:full, :retained] do
    {specs, dropped} = export_plan(policy, mode)

    tenant_session(context, fn ->
      {:ok,
       Map.new(specs, fn spec ->
         rows =
           spec
           |> per_scope(context, &adapter().export/3, &(&2 ++ &1), [])
           |> RetentionReview.strip_columns(dropped)

         {spec.table, rows}
       end)}
    end)
  end

  def export(_policy, _context, _mode), do: {:error, :organization_context_required}

  @doc "Deletes the context's tenant rows in declared order, atomically."
  def purge(policy, %PurgeContext{organization_id: organization_id} = context)
      when is_binary(organization_id) do
    tenant_session(context, fn ->
      adapter().transaction(fn ->
        {:ok,
         Enum.reduce(policy.tables, %{}, fn spec, deleted ->
           Map.put(
             deleted,
             spec.table,
             per_scope(spec, context, &adapter().delete/3, &+/2, 0)
           )
         end)}
      end)
    end)
  end

  def purge(_policy, _context), do: {:error, :organization_context_required}

  defp export_plan(policy, :full), do: {policy.tables, policy.excluded_columns}

  defp export_plan(policy, :retained) do
    retained = RetentionReview.retained_tables(policy)
    specs = Enum.filter(policy.tables, &(&1.table in retained))

    dropped =
      if policy.disposition == :retain_anonymized,
        do: policy.excluded_columns ++ policy.anonymized_columns,
        else: policy.excluded_columns

    {specs, dropped}
  end

  defp per_scope(spec, %PurgeContext{} = context, operation, combine, initial) do
    case Map.get(spec, :rls, :organization) do
      :organization ->
        operation.(spec, context.organization_id, nil)

      _personal ->
        Enum.reduce(context.subject_user_ids, initial, fn user_id, acc ->
          result =
            RepoContext.run(%{organization_id: context.organization_id, user_id: user_id}, fn ->
              operation.(spec, context.organization_id, user_id)
            end)

          combine.(result, acc)
        end)
    end
  end

  defp tenant_session(%PurgeContext{} = context, fun) do
    RepoContext.run(%{organization_id: context.organization_id, user_id: context.user_id}, fun)
  end

  defp adapter do
    Application.get_env(
      :milos_training,
      :tenant_table_store,
      MilosTraining.Infrastructure.TenantData.EctoTableStore
    )
  end
end
