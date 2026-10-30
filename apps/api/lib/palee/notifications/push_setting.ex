defmodule Palee.Notifications.PushSetting do
  @moduledoc """
  The installation's one Web Push row (ADR-277): the key pair the server made
  and the contact for push services. The private key is encrypted at rest.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Infrastructure.Security.EncryptedBinary

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notification_push_settings" do
    field :singleton, :boolean, default: true
    field :vapid_public_key, :string

    field :vapid_private_key, EncryptedBinary,
      source: :vapid_private_key_encrypted,
      redact: true

    field :vapid_subject, :string
    field :keys_created_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def keys_changeset(settings \\ %__MODULE__{}, %{public_key: public, private_key: private}) do
    change(settings,
      vapid_public_key: public,
      vapid_private_key: private,
      keys_created_at: DateTime.utc_now()
    )
  end

  def subject_changeset(settings \\ %__MODULE__{}, subject) do
    settings
    |> change(vapid_subject: subject)
    |> validate_required([:vapid_subject])
    |> validate_length(:vapid_subject, max: 255)
  end
end
