defmodule MilosTraining.Application.SignOutAllDevices do
  alias MilosTraining.Identity

  def call(%{id: user_id}) do
    with {:ok, _user} <- Identity.bump_security_version(user_id), do: :ok
  end
end
