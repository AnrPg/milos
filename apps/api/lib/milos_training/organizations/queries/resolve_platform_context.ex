defmodule MilosTraining.Organizations.Queries.ResolvePlatformContext do
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}

  def call(account, request_metadata \\ %{})

  def call(%{id: user_id} = account, request_metadata) do
    # Same reason as ResolveTenantContext: the vendors policy keys on
    # app.user_id, so the lookup has to run inside a user-scoped session.
    case RepoContext.run(%{user_id: user_id}, fn -> OrganizationStore.get_vendor(user_id) end) do
      nil ->
        {:error, :vendor_required}

      vendor ->
        {:ok,
         %PlatformContext{
           account: account,
           vendor: vendor,
           user_id: user_id,
           request_metadata: request_metadata || %{}
         }}
    end
  end

  def call(_account, _request_metadata), do: {:error, :vendor_required}
end
