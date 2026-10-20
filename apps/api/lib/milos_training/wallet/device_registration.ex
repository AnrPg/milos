defmodule MilosTraining.Wallet.DeviceRegistration do
  @moduledoc "An Apple device that asked for updates of a pass (PassKit web service, ADR-155)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "wallet_device_registrations" do
    field :pass_id, :binary_id
    field :device_library_id, :string
    field :push_token, :string, redact: true

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(registration \\ %__MODULE__{}, attrs) do
    registration
    |> cast(attrs, [:pass_id, :device_library_id, :push_token])
    |> validate_required([:pass_id, :device_library_id, :push_token])
    |> validate_length(:device_library_id, max: 255)
    |> validate_length(:push_token, max: 255)
    |> unique_constraint([:device_library_id, :pass_id])
  end
end
