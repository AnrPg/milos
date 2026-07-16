defmodule MilosTraining.Notifications.PushSetting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notification_push_settings" do
    field :vapid_public_key, :string
    field :vapid_private_key, :string
    field :vapid_subject, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(settings \\ %__MODULE__{}, params) do
    settings
    |> cast(params, [:vapid_public_key, :vapid_private_key, :vapid_subject])
    |> normalize_blank(:vapid_public_key)
    |> normalize_blank(:vapid_private_key)
    |> normalize_blank(:vapid_subject)
    |> validate_length(:vapid_public_key, max: 512)
    |> validate_length(:vapid_private_key, max: 512)
    |> validate_length(:vapid_subject, max: 255)
  end

  defp normalize_blank(changeset, field) do
    case get_change(changeset, field) do
      value when is_binary(value) ->
        put_change(changeset, field, blank_to_nil(String.trim(value)))

      _ ->
        changeset
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
