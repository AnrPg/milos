defmodule MilosTraining.Organizations.Queries.ResolvePlatformContext do
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}

  def call(account, request_metadata \\ %{})

  def call(%{id: user_id} = account, request_metadata) do
    case OrganizationStore.get_vendor(user_id) do
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
