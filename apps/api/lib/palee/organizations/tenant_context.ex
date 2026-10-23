defmodule Palee.Organizations.TenantContext do
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
    roles: [],
    capabilities: %{},
    coach_scope: :own,
    # ADR-186: the branches this person works at as staff, or :all.
    location_scope: :all,
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
          roles: [atom()],
          capabilities: %{atom() => :all | :own | :status},
          coach_scope: :own | :all,
          location_scope: :all | [Ecto.UUID.t()],
          request_metadata: map()
        }
end
