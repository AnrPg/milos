defmodule MilosTraining.Application.AuthorizeFinanceEntitlement do
  alias MilosTraining.Finance
  alias MilosTraining.Finance.Domain.EntitlementPolicy

  def call(user_id, capability) do
    user_id
    |> Finance.get_entitlement()
    |> EntitlementPolicy.authorize(capability)
  end
end
