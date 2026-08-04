defmodule MilosTraining.Organizations.Queries.ResolvePlatformContext do
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}

  def call(account, request_metadata \\ %{})

  def call(%{id: user_id} = account, request_metadata) do
    case OrganizationStore.get_platform_owner(user_id) do
      nil ->
        {:error, :platform_owner_required}

      platform_owner ->
        {:ok,
         %PlatformContext{
           account: account,
           platform_owner: platform_owner,
           user_id: user_id,
           request_metadata: request_metadata || %{}
         }}
    end
  end

  def call(_account, _request_metadata), do: {:error, :platform_owner_required}
end
