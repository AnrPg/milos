defmodule MilosTraining.Application.AvatarStorage do
  def create_upload(user_id, content_type, byte_size),
    do: impl().create_upload(user_id, content_type, byte_size)

  def validate_uploaded(user_id, key), do: impl().validate_uploaded(user_id, key)

  defp impl, do: Application.fetch_env!(:milos_training, :avatar_storage)
end
