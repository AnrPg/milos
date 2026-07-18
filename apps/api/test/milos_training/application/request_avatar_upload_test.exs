defmodule MilosTraining.Application.RequestAvatarUploadTest do
  use ExUnit.Case, async: false

  alias MilosTraining.Application.RequestAvatarUpload

  setup do
    original_avatar_storage = Application.fetch_env!(:milos_training, :avatar_storage)
    Application.put_env(:milos_training, :avatar_storage, __MODULE__.AvatarStorage)

    on_exit(fn ->
      Application.put_env(:milos_training, :avatar_storage, original_avatar_storage)
    end)
  end

  test "accepts supported browser image source formats" do
    for content_type <- ~w(image/jpeg image/png image/webp image/gif image/bmp image/avif) do
      assert {:ok, %{required_headers: %{"content-type" => ^content_type}}} =
               RequestAvatarUpload.call("user-id", %{
                 "content_type" => content_type,
                 "byte_size" => 1024
               })
    end
  end

  test "rejects unsupported avatar source formats" do
    assert RequestAvatarUpload.call("user-id", %{
             "content_type" => "image/svg+xml",
             "byte_size" => 1024
           }) == {:error, :invalid_avatar_upload}
  end

  defmodule AvatarStorage do
    @behaviour MilosTraining.Application.Ports.AvatarStorage

    @impl true
    def create_upload(_user_id, content_type, _byte_size) do
      {:ok, %{required_headers: %{"content-type" => content_type}}}
    end

    @impl true
    def validate_uploaded(_user_id, _key), do: {:error, :not_used}
  end
end
