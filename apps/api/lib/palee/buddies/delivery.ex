defmodule Palee.Buddies.Delivery do
  @moduledoc "Who received a support request, silently or not, and when they replied (ADR-160)."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "support_request_deliveries" do
    field :request_id, :binary_id
    field :user_id, :binary_id
    field :buddy_user_id, :binary_id
    field :delivered_silently, :boolean, default: false
    field :replied_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
