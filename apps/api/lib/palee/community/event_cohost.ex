defmodule Palee.Community.EventCohost do
  @moduledoc """
  A co-host of an event (ADR-185 §5): another box the host invited. The row
  lives in the host's tenant (`organization_id`); the co-host's staff see
  and answer it only through narrow definer functions. `pending` until
  they accept or decline; an accepted co-host may withdraw (`removed`), and
  the host may remove it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending accepted declined removed)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "community_event_cohosts" do
    field :organization_id, :binary_id, read_after_writes: true
    field :event_id, :binary_id
    field :cohost_organization_id, :binary_id
    field :status, :string, default: "pending"
    field :invited_by_id, :binary_id
    field :responded_by_id, :binary_id
    field :responded_at, :utc_datetime_usec
    field :trial_offer_sent_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :event_id, :cohost_organization_id, :invited_by_id])
    |> validate_required([:organization_id, :event_id, :cohost_organization_id])
    |> put_change(:status, "pending")
    |> check_constraint(:cohost_organization_id, name: :community_event_cohosts_self_check)
    |> unique_constraint([:event_id, :cohost_organization_id],
      name: :community_event_cohosts_event_id_cohost_organization_id_index,
      message: "already_invited"
    )
  end

  @doc "The host takes a co-host off, or asks again after a decline or removal."
  def status_changeset(cohost, attrs) do
    cohost
    |> cast(attrs, [:status, :responded_at, :responded_by_id, :invited_by_id])
    |> validate_inclusion(:status, @statuses)
    |> check_constraint(:status, name: :community_event_cohosts_answer_check)
  end
end
