defmodule MilosTraining.Application.NicknameAvailability do
  alias MilosTraining.Identity

  def call(nickname) when is_binary(nickname),
    do: {:ok, is_nil(Identity.find_by_nickname(nickname))}

  def call(_nickname), do: {:error, :bad_request}
end
