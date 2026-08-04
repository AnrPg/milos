defmodule MilosTraining.Application.OwnershipKeys do
  def tenant(%{organization_id: organization_id}, suffix)
      when is_binary(organization_id) and is_binary(suffix) and suffix != "" do
    "org:#{organization_id}:#{suffix}"
  end

  def user(%{user_id: user_id}, suffix)
      when is_binary(user_id) and is_binary(suffix) and suffix != "" do
    "user:#{user_id}:#{suffix}"
  end

  def tenant_object(%{organization_id: organization_id}, relative_path)
      when is_binary(organization_id) and is_binary(relative_path) do
    "organizations/#{organization_id}/#{clean_relative_path(relative_path)}"
  end

  def user_object(%{user_id: user_id}, relative_path)
      when is_binary(user_id) and is_binary(relative_path) do
    "users/#{user_id}/#{clean_relative_path(relative_path)}"
  end

  def require_tenant_args(%{"organization_id" => organization_id} = args)
      when is_binary(organization_id) and organization_id != "",
      do: {:ok, args}

  def require_tenant_args(_args), do: {:error, :missing_organization_scope}

  def require_user_args(%{"owner_user_id" => user_id} = args)
      when is_binary(user_id) and user_id != "",
      do: {:ok, args}

  def require_user_args(_args), do: {:error, :missing_user_scope}

  defp clean_relative_path(path) do
    path
    |> String.trim_leading("/")
    |> String.split("/", trim: true)
    |> Enum.reject(&(&1 in [".", ".."]))
    |> Enum.join("/")
  end
end
