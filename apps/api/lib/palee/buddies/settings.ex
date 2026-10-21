defmodule Palee.Buddies.Settings do
  @moduledoc "A person's buddy settings: quiet hours and phone sharing (ADR-160)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "buddy_settings" do
    field :user_id, :binary_id
    field :quiet_from, :time
    field :quiet_to, :time
    field :tz, :string, default: "Europe/Athens"
    field :share_phone, :boolean, default: false
    field :phone, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:user_id, :quiet_from, :quiet_to, :tz, :share_phone, :phone])
    |> validate_required([:user_id, :tz])
    |> check_constraint(:quiet_from, name: :buddy_settings_quiet_check)
    |> check_constraint(:phone, name: :buddy_settings_phone_check)
  end
end
