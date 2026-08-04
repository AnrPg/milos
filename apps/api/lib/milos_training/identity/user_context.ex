defmodule MilosTraining.Identity.UserContext do
  @enforce_keys [:account, :user_id]
  defstruct [:account, :user_id, request_metadata: %{}]

  @type t :: %__MODULE__{account: struct(), user_id: Ecto.UUID.t(), request_metadata: map()}

  def new(%{id: user_id} = account, request_metadata \\ %{}) do
    %__MODULE__{account: account, user_id: user_id, request_metadata: request_metadata || %{}}
  end
end
