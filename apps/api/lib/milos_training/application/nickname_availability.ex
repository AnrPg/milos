defmodule MilosTraining.Application.NicknameAvailability do
  alias MilosTraining.{Identity, Identity.RegistrationPolicy}

  def call(nickname) when is_binary(nickname) do
    if RegistrationPolicy.valid_nickname?(nickname) do
      {:ok, is_nil(Identity.find_by_nickname(RegistrationPolicy.normalize_nickname(nickname)))}
    else
      {:error, :bad_request}
    end
  end

  def call(_nickname), do: {:error, :bad_request}
end
