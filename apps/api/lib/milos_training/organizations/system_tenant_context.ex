defmodule MilosTraining.Organizations.SystemTenantContext do
  @enforce_keys [:organization, :organization_id, :source]
  defstruct [:organization, :organization_id, :source, request_metadata: %{}]

  @type t :: %__MODULE__{
          organization: struct(),
          organization_id: Ecto.UUID.t(),
          source: atom(),
          request_metadata: map()
        }
end
