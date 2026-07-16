defmodule MilosTraining.Application.RequestAvatarUpload do
  alias MilosTraining.Application.AvatarStorage

  @allowed_types ~w(image/jpeg image/png image/webp)
  @max_bytes 5 * 1_024 * 1_024

  def call(user_id, params) do
    content_type = params[:content_type] || params["content_type"]
    byte_size = params[:byte_size] || params["byte_size"]

    if content_type in @allowed_types and is_integer(byte_size) and byte_size > 0 and
         byte_size <= @max_bytes do
      AvatarStorage.create_upload(user_id, content_type, byte_size)
    else
      {:error, :invalid_avatar_upload}
    end
  end
end
