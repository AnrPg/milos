defmodule MilosTraining.Organizations.PlatformContext do
  @enforce_keys [:account, :vendor, :user_id]
  defstruct [:account, :vendor, :user_id, request_metadata: %{}]

  @type t :: %__MODULE__{
          account: struct(),
          vendor: struct(),
          user_id: Ecto.UUID.t(),
          request_metadata: map()
        }
end
