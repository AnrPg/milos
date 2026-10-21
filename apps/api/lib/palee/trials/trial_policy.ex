defmodule Palee.Trials.TrialPolicy do
  @moduledoc """
  The owner's trial rules for one box (ADR-144, board 6 Q3). Off until the
  owner turns them on; a box without a row has the defaults below, disabled.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @approvals ~w(auto manual)
  @editable [
    :enabled,
    :approval,
    :weekly_limit,
    :per_person_limit,
    :seats_per_class,
    :class_type_ids,
    :horizon_days,
    :first_timers_only,
    :no_show_consumes,
    :bring_note,
    :conversion_package_id
  ]

  @type t :: %__MODULE__{}

  schema "scheduling_trial_policies" do
    field :organization_id, :binary_id
    field :enabled, :boolean, default: false
    field :approval, :string, default: "auto"
    field :weekly_limit, :integer
    field :per_person_limit, :integer, default: 1
    field :seats_per_class, :integer, default: 2
    field :class_type_ids, {:array, :binary_id}, default: []
    field :horizon_days, :integer
    field :first_timers_only, :boolean, default: false
    field :no_show_consumes, :boolean, default: false
    field :bring_note, :string
    field :conversion_package_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc "The rules of a box that never saved any: everything off."
  def default(organization_id), do: %__MODULE__{organization_id: organization_id}

  def changeset(policy, attrs) do
    policy
    |> cast(attrs, @editable)
    |> validate_required([:organization_id, :enabled, :approval, :per_person_limit])
    |> validate_inclusion(:approval, @approvals)
    |> validate_number(:weekly_limit, greater_than_or_equal_to: 1, less_than_or_equal_to: 500)
    |> validate_number(:per_person_limit, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:seats_per_class, greater_than_or_equal_to: 1, less_than_or_equal_to: 50)
    |> validate_number(:horizon_days, greater_than_or_equal_to: 1, less_than_or_equal_to: 90)
    |> validate_length(:bring_note, max: 600)
    |> update_change(:class_type_ids, &Enum.uniq/1)
    |> validate_length(:class_type_ids, max: 100)
    |> foreign_key_constraint(:conversion_package_id)
    |> unique_constraint(:organization_id)
  end

  def editable_fields, do: @editable
  def approvals, do: @approvals
end
