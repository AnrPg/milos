defmodule MilosTraining.Application.DocumentStorage do
  @behaviour MilosTraining.Application.Ports.DocumentStorage

  alias MilosTraining.Application.OwnershipKeys

  @impl true
  def presigned_upload_post(key, policy), do: impl().presigned_upload_post(key, policy)
  @impl true
  def presigned_download_url(key), do: impl().presigned_download_url(key)
  @impl true
  def validate_uploaded_document(key, policy), do: impl().validate_uploaded_document(key, policy)

  def tenant_upload_post(%{organization_id: _} = context, relative_path, policy) do
    key = OwnershipKeys.tenant_object(context, relative_path)

    with {:ok, upload} <- presigned_upload_post(key, policy) do
      {:ok, Map.put(upload, :key, key)}
    end
  end

  def tenant_upload_post(_context, _relative_path, _policy),
    do: {:error, :missing_organization_scope}

  def validate_tenant_upload(%{organization_id: organization_id}, key, policy)
      when is_binary(organization_id) and is_binary(key) do
    expected_prefix = "organizations/#{organization_id}/"

    if String.starts_with?(key, expected_prefix),
      do: validate_uploaded_document(key, policy),
      else: {:error, :document_key_forbidden}
  end

  def validate_tenant_upload(_context, _key, _policy), do: {:error, :missing_organization_scope}

  def tenant_download_url(%{organization_id: organization_id}, key)
      when is_binary(organization_id) and is_binary(key) do
    expected_prefix = "organizations/#{organization_id}/"

    if String.starts_with?(key, expected_prefix),
      do: presigned_download_url(key),
      else: {:error, :document_key_forbidden}
  end

  def tenant_download_url(_context, _key), do: {:error, :missing_organization_scope}

  defp impl, do: Application.fetch_env!(:milos_training, :document_storage)
end
