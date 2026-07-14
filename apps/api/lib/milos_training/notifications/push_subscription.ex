defmodule MilosTraining.Notifications.PushSubscription do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "push_subscriptions" do
    field :user_id, :binary_id
    field :endpoint, :string
    field :p256dh_key, :string
    field :auth_key, :string
    field :expiration_time, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(subscription \\ %__MODULE__{}, params) do
    subscription
    |> cast(params, [:user_id, :endpoint, :p256dh_key, :auth_key, :expiration_time])
    |> validate_required([:user_id, :endpoint, :p256dh_key, :auth_key])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:endpoint, name: :push_subscriptions_endpoint_index)
  end
end
