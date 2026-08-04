defmodule MilosTraining.Application.DocumentStorage do
  @behaviour MilosTraining.Application.Ports.DocumentStorage

  alias MilosTraining.Application.OwnershipKeys

  @impl true
  def presigned_upload_url(key), do: impl().presigned_upload_url(key)
  @impl true
  def presigned_download_url(key), do: impl().presigned_download_url(key)

  def tenant_upload_url(%{organization_id: _} = context, relative_path) do
    key = OwnershipKeys.tenant_object(context, relative_path)

    with {:ok, url} <- presigned_upload_url(key) do
      {:ok, %{url: url, key: key}}
    end
  end

  def tenant_upload_url(_context, _relative_path), do: {:error, :missing_organization_scope}

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
