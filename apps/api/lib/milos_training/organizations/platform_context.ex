defmodule MilosTraining.Organizations.PlatformContext do
  @enforce_keys [:account, :platform_owner, :user_id]
  defstruct [:account, :platform_owner, :user_id, request_metadata: %{}]

  @type t :: %__MODULE__{
          account: struct(),
          platform_owner: struct(),
          user_id: Ecto.UUID.t(),
          request_metadata: map()
        }
end
