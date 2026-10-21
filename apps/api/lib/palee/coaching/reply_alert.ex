defmodule Palee.Coaching.ReplyAlert do
  @moduledoc "Marks a client message whose overdue reply staff were already told about (ADR-098)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "coaching_reply_alerts" do
    field :organization_id, :binary_id
    field :message_id, :binary_id
    field :thread_id, :binary_id
    field :notified_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(params) do
    %__MODULE__{}
    |> cast(params, [:organization_id, :message_id, :thread_id, :notified_at])
    |> validate_required([:organization_id, :message_id, :thread_id, :notified_at])
    |> unique_constraint([:organization_id, :message_id])
  end
end
