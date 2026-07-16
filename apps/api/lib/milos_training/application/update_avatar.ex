defmodule MilosTraining.Application.UpdateAvatar do
  alias MilosTraining.Application.AvatarStorage
  alias MilosTraining.Identity

  def call(user_id, nil), do: Identity.update_avatar(user_id, nil)

  def call(user_id, key) when is_binary(key) do
    with {:ok, public_url} <- AvatarStorage.validate_uploaded(user_id, key) do
      Identity.update_avatar(user_id, public_url)
    end
  end

  def call(_user_id, _key), do: {:error, :invalid_avatar_upload}
end
