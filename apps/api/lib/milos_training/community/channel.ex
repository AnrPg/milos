defmodule MilosTraining.Community.Channel do
  @moduledoc """
  A channel inside a club (ADR-138). A `member_group` is one a member
  proposed in their gym's club (ADR-143): it has a creator, a join policy and,
  while staff haven't decided, a `pending` status. A `pt_squad` is a coach's
  invite-only channel with their own clients (ADR-168); its creator is the
  coach.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(announcements wod challenges class_slot season custom member_group general pt_squad)
  @write_policies ~w(staff members participants system_and_members)
  @memberships ~w(everyone opt_in invite)
  @join_policies ~w(open request)
  @statuses ~w(pending active declined)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_channels" do
    field :organization_id, :binary_id, read_after_writes: true
    field :club_id, :binary_id
    field :kind, :string
    field :name, :string
    field :write_policy, :string
    field :membership, :string
    field :context_type, :string
    field :context_id, :binary_id
    field :position, :integer, default: 0
    field :description, :string
    field :created_by_id, :binary_id
    field :join_policy, :string
    field :status, :string, default: "active"
    field :decided_by_id, :binary_id
    field :decided_at, :utc_datetime_usec
    field :last_post_at, :utc_datetime_usec
    field :archive_warned_at, :utc_datetime_usec
    field :archived_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(channel \\ %__MODULE__{}, attrs) do
    channel
    |> cast(attrs, [
      :organization_id,
      :club_id,
      :kind,
      :name,
      :write_policy,
      :membership,
      :context_type,
      :context_id,
      :position,
      :description,
      :created_by_id,
      :join_policy,
      :status,
      :archived_at
    ])
    |> update_change(:name, &String.trim/1)
    |> update_change(:description, &blank_to_nil/1)
    |> validate_required([:club_id, :kind, :write_policy, :membership])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:write_policy, @write_policies)
    |> validate_inclusion(:membership, @memberships)
    |> validate_length(:name, max: 60)
    |> validate_length(:description, max: 200)
    |> validate_inclusion(:join_policy, @join_policies)
    |> validate_inclusion(:status, @statuses)
    |> validate_group()
    |> unique_constraint(:name, name: :community_channels_group_name_index)
    |> unique_constraint(:name, name: :community_channels_squad_name_index)
    |> check_constraint(:join_policy, name: :community_channels_join_policy_check)
    |> check_constraint(:name, name: :community_channels_name_check)
    |> check_constraint(:context_id, name: :community_channels_context_check)
    |> unique_constraint(:kind, name: :community_channels_one_builtin_index)
    |> unique_constraint(:context_id, name: :community_channels_one_per_context_index)
  end

  @doc "What a group's admins may change about it."
  def group_changeset(channel, attrs) do
    channel
    |> cast(attrs, [:name, :description, :join_policy])
    |> update_change(:name, &String.trim/1)
    |> update_change(:description, &blank_to_nil/1)
    |> validate_required([:name, :join_policy])
    |> validate_length(:name, min: 2, max: 60)
    |> validate_length(:description, max: 200)
    |> validate_inclusion(:join_policy, @join_policies)
    |> unique_constraint(:name, name: :community_channels_group_name_index)
  end

  @doc "What a squad's coach may change about it (ADR-168)."
  def squad_changeset(channel, attrs) do
    channel
    |> cast(attrs, [:name, :description])
    |> update_change(:name, &String.trim/1)
    |> update_change(:description, &blank_to_nil/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 60)
    |> validate_length(:description, max: 200)
    |> unique_constraint(:name, name: :community_channels_squad_name_index)
  end

  @doc "Staff decisions and the quiet-group lifecycle."
  def lifecycle_changeset(channel, attrs) do
    channel
    |> cast(attrs, [
      :status,
      :decided_by_id,
      :decided_at,
      :archived_at,
      :archive_warned_at,
      :last_post_at
    ])
    |> validate_inclusion(:status, @statuses)
  end

  def kinds, do: @kinds
  def join_policies, do: @join_policies

  defp validate_group(changeset) do
    case get_field(changeset, :kind) do
      "member_group" ->
        changeset
        |> validate_required([:name, :join_policy, :created_by_id])
        |> validate_length(:name, min: 2)

      "pt_squad" ->
        changeset
        |> put_change(:join_policy, nil)
        |> validate_required([:name, :created_by_id])
        |> validate_length(:name, min: 2)

      _other ->
        put_change(changeset, :join_policy, nil)
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value), do: value |> String.trim() |> then(&if(&1 == "", do: nil, else: &1))
end
