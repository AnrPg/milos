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

  @type t :: %__MODULE__{
          organization: struct(),
          membership: struct(),
          account: struct(),
          organization_id: Ecto.UUID.t(),
          membership_id: Ecto.UUID.t(),
          user_id: Ecto.UUID.t(),
          role: atom(),
          request_metadata: map()
        }
end
