defmodule MilosTraining.Partners.Match do
  @moduledoc """
  Two people who liked each other in a club (ADR-169): the pair ordered
  `user_a_id < user_b_id`, at most one active per gym; how it ended; each
  side's read mark of the conversation.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Partners.Domain.MatchPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "partner_matches" do
    field :organization_id, :binary_id, read_after_writes: true
    field :club_id, :binary_id
    field :user_a_id, :binary_id
    field :user_b_id, :binary_id
    field :status, :string, default: "active"
    field :matched_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :ended_by_id, :binary_id
    field :end_reason, :string
    field :a_read_at, :utc_datetime_usec
    field :b_read_at, :utc_datetime_usec
    field :last_message_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :club_id, :user_a_id, :user_b_id, :matched_at])
    |> validate_required([:club_id, :user_a_id, :user_b_id, :matched_at])
    |> check_constraint(:user_b_id, name: :partner_matches_pair_check)
    |> unique_constraint([:user_a_id, :user_b_id], name: :partner_matches_active_pair_index)
  end

  def changeset(match, attrs) do
    match
    |> cast(attrs, [
      :status,
      :ended_at,
      :ended_by_id,
      :end_reason,
      :a_read_at,
      :b_read_at,
      :last_message_at
    ])
    |> validate_inclusion(:status, MatchPolicy.statuses())
    |> validate_inclusion(:end_reason, MatchPolicy.end_reasons())
    |> check_constraint(:status, name: :partner_matches_end_check)
  end
end
