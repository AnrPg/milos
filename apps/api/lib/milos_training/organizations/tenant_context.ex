defmodule MilosTraining.Organizations.TenantContext do
  @enforce_keys [
    :organization,
    :membership,
    :account,
    :organization_id,
    :membership_id,
    :user_id,
    :role
  ]
  defstruct [
    :organization,
    :membership,
    :account,
    :organization_id,
    :membership_id,
    :user_id,
    :role,
    request_metadata: %{}
  ]
end
