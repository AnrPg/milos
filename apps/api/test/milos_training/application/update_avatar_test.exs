defmodule MilosTraining.Application.UpdateAvatarTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Application.UpdateAvatar
  alias MilosTraining.Identity

  setup do
    original_avatar_storage = Application.fetch_env!(:milos_training, :avatar_storage)

    Application.put_env(:milos_training, :avatar_storage, __MODULE__.AvatarStorage)

    on_exit(fn ->
      Application.put_env(:milos_training, :avatar_storage, original_avatar_storage)
    end)
  end

  test "persists the public URL returned by avatar storage" do
    {:ok, user} =
      Identity.register(%{
        nickname: "avatar_member",
        password: "S3cur3P@ss!",
        role: :member
      })

    avatar_key = "avatars/#{user.id}/avatar.jpg"

    assert {:ok, updated_user} = UpdateAvatar.call(user.id, avatar_key)
    assert updated_user.avatar_url == "https://s3-milos.4kq.net/milos-avatars/#{avatar_key}"
    assert Identity.find_by_id(user.id).avatar_url == updated_user.avatar_url
  end

  defmodule AvatarStorage do
    @behaviour MilosTraining.Application.Ports.AvatarStorage

    @impl true
    def create_upload(_user_id, _content_type, _byte_size), do: {:error, :not_used}

    @impl true
    def validate_uploaded(user_id, "avatars/" <> _rest = key) do
      if String.starts_with?(key, "avatars/#{user_id}/") do
        {:ok, "https://s3-milos.4kq.net/milos-avatars/#{key}"}
      else
        {:error, :invalid_avatar_upload}
      end
    end
  end
end
