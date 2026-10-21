defmodule Palee.Buddies.Link do
  @moduledoc "A buddy link between a member and the person who supports them (ADR-160)."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Buddies.Domain.LinkPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "buddy_links" do
    field :user_id, :binary_id
    field :buddy_user_id, :binary_id
    field :invite_token_hash, :binary, redact: true
    field :status, :string, default: "pending"
    field :receives_weekly_summary, :boolean, default: false
    field :expires_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :ended_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(status receives_weekly_summary expires_at started_at ended_at ended_by_id)a

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:user_id, :buddy_user_id, :invite_token_hash | @fields])
    |> validate_required([:user_id, :status])
    |> validate_inclusion(:status, LinkPolicy.statuses())
    |> check_constraint(:buddy_user_id, name: :buddy_links_party_check)
    |> unique_constraint([:user_id, :buddy_user_id], name: :buddy_links_open_pair_index)
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, @fields)
    |> validate_inclusion(:status, LinkPolicy.statuses())
  end
end
