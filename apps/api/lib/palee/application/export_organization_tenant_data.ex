defmodule Palee.Application.ExportOrganizationTenantData do
  @moduledoc """
  ADR-117 stage 2. Builds, under the tenant's object prefix:

  * `purge/<purge_id>/tenant-export.zip` - one JSON file per bounded context,
    account records, the stored-objects manifest and the retention review;
  * `retained/<purge_id>/retention-archive.zip` - only rows a context policy
    retains (anonymized where required), kept after the purge.

  Then records the export metadata and per-context retention review on the
  purge record. Every context read runs through that context's public API with
  the purge's `PurgeContext`. Re-running is safe: objects are overwritten.
  """

  alias Palee.{Identity, Organizations}
  alias Palee.Application.{TenantDataContexts, TenantObjectStorage}
  alias Palee.TenantData.Domain.{ExportBundle, RetentionReview}

  def call(platform_context, purge_id, now \\ DateTime.utc_now()) do
    with {:ok, purge} <-
           Organizations.advance_organization_purge(
             platform_context,
             purge_id,
             :start_export,
             %{},
             now
           ),
         {:ok, attrs} <- build_export(platform_context, purge, now) do
      Organizations.advance_organization_purge(
        platform_context,
        purge.id,
        :complete_export,
        attrs,
        DateTime.utc_now()
      )
    else
      {:error, reason} -> fail(platform_context, purge_id, reason)
    end
  end

  defp build_export(platform_context, purge, now) do
    with {:ok, scope} <- Organizations.tenant_purge_context(platform_context, purge),
         {:ok, %{organization: organization}} <-
           Organizations.list_organization_memberships(platform_context, purge.organization_id),
         {:ok, deletable_ids} <-
           Organizations.list_deletable_organization_user_ids(
             platform_context,
             purge.organization_id
           ),
         {:ok, full_sections, retained_sections, inventories} <- export_contexts(scope),
         {:ok, objects} <-
           TenantObjectStorage.inventory(purge.organization_id, scope.subject_user_ids) do
      policies = TenantDataContexts.policies()
      retained_prefixes = RetentionReview.retained_object_prefixes(policies)
      today = DateTime.to_date(now)

      review =
        Enum.map(inventories, fn {policy, inventory} ->
          RetentionReview.entry(policy, inventory, today)
        end) ++
          [
            RetentionReview.identity_entry(
              length(deletable_ids),
              length(scope.subject_user_ids) - length(deletable_ids)
            ),
            RetentionReview.storage_entry(objects.documents, objects.avatars, retained_prefixes)
          ]

      organization_doc = %{
        "id" => organization.id,
        "slug" => organization.slug,
        "name" => organization.name,
        "status" => to_string(organization.status)
      }

      with {:ok, export_zip} <-
             ExportBundle.full_export(%{
               purge_id: purge.id,
               organization: organization_doc,
               generated_at: now,
               sections: full_sections,
               accounts: Identity.export_accounts(scope.subject_user_ids),
               objects: objects,
               retention_review: review
             }),
           {:ok, retained_zip} <-
             ExportBundle.retention_archive(%{
               purge_id: purge.id,
               organization: organization_doc,
               generated_at: now,
               sections: retained_sections,
               retention_review: review,
               retained_object_prefixes: retained_prefixes
             }),
           {:ok, export_key} <-
             TenantObjectStorage.put_tenant_object(
               purge.organization_id,
               RetentionReview.export_object_path(purge.id),
               export_zip,
               "application/zip"
             ),
           {:ok, retained_key} <-
             TenantObjectStorage.put_tenant_object(
               purge.organization_id,
               RetentionReview.retained_archive_path(purge.id),
               retained_zip,
               "application/zip"
             ) do
        {:ok,
         %{
           export_key: export_key,
           export_byte_size: byte_size(export_zip),
           export_sha256: ExportBundle.sha256(export_zip),
           retained_archive_key: retained_key,
           retention_review: review
         }}
      end
    end
  end

  # Organizations is exported with the purgeable contexts (it is purged last,
  # by deleting the organization row).
  defp export_contexts(scope) do
    modules =
      Enum.map(TenantDataContexts.purge_sequence(), &elem(&1, 0)) ++ [Organizations]

    Enum.reduce_while(modules, {:ok, [], [], []}, fn module, {:ok, full, retained, inventories} ->
      policy = module.tenant_data_policy()

      with {:ok, inventory} <- module.tenant_data_inventory(scope),
           {:ok, tables} <- module.export_tenant_data(scope, :full),
           {:ok, retained_tables} <- retained_export(module, policy, scope) do
        retained =
          if retained_tables == %{},
            do: retained,
            else: retained ++ [%{policy: policy, tables: retained_tables}]

        {:cont,
         {:ok, full ++ [%{policy: policy, tables: tables}], retained,
          inventories ++ [{policy, inventory}]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp retained_export(_module, %{disposition: :purge}, _scope), do: {:ok, %{}}
  defp retained_export(module, _policy, scope), do: module.export_tenant_data(scope, :retained)

  defp fail(platform_context, purge_id, reason) do
    _ =
      Organizations.advance_organization_purge(platform_context, purge_id, :fail, %{
        stage: "export",
        reason: reason
      })

    {:error, reason}
  end
end
