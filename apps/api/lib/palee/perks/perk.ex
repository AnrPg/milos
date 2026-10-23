defmodule Palee.Perks.Perk do
  @moduledoc """
  A partner perk (ADR-191): the partner, the redemption method, the
  branches it is valid at, its lifecycle and counters. What members agree
  to (benefit, rules, settings, terms) is its current `PerkVersion`,
  loaded into the virtual `version` by the store. `valid_from` /
  `valid_until` mirror that version's window for queries.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Perks.Domain.{PerkRules, RedemptionMethod}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @editable ~w(partner_name partner_url partner_address logo_media_id redemption_method
               all_locations location_ids)a

  @type t :: %__MODULE__{}

  schema "perks" do
    field :organization_id, :binary_id, read_after_writes: true
    field :partner_name, :string
    field :partner_url, :string
    field :partner_address, :string
    field :logo_media_id, :binary_id
    field :redemption_method, :string
    field :current_version, :integer, default: 1
    field :valid_from, :date
    field :valid_until, :date
    field :all_locations, :boolean, default: true
    field :location_ids, {:array, :binary_id}, default: []
    field :status, :string, default: "draft"
    field :claims_count, :integer, default: 0
    field :uses_count, :integer, default: 0
    field :published_at, :utc_datetime_usec
    field :paused_at, :utc_datetime_usec
    field :expired_at, :utc_datetime_usec
    field :created_by_id, :binary_id
    field :updated_by_id, :binary_id
    field :version, :any, virtual: true

    timestamps(type: :utc_datetime_usec)
  end

  def editable_fields, do: @editable

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :created_by_id, :updated_by_id | @editable])
    |> validate_required([:organization_id])
    |> validate()
  end

  def update_changeset(%__MODULE__{} = perk, attrs) do
    perk
    |> cast(attrs, [:updated_by_id, :current_version, :valid_from, :valid_until | @editable])
    |> validate()
  end

  @doc "A lifecycle step's changes (`PerkRules.transition/4`)."
  def status_changeset(%__MODULE__{} = perk, changes) do
    perk
    |> change(changes)
    |> validate_inclusion(:status, PerkRules.statuses())
  end

  defp validate(changeset) do
    changeset
    |> update_change(:partner_name, &trim/1)
    |> validate_required([:partner_name, :redemption_method])
    |> validate_length(:partner_name, min: 1, max: 120)
    |> validate_length(:partner_url, max: 500)
    |> validate_length(:partner_address, max: 300)
    |> validate_format(:partner_url, ~r/^https?:\/\/[^\s]+$/i, message: "must be an http(s) link")
    |> validate_inclusion(:redemption_method, RedemptionMethod.keys())
    |> validate_branches()
    |> check_constraint(:valid_until, name: :perks_window_check)
    |> check_constraint(:location_ids, name: :perks_location_scope_check)
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value

  defp validate_branches(changeset) do
    if get_field(changeset, :all_locations) == false and
         (get_field(changeset, :location_ids) || []) == [],
       do: add_error(changeset, :location_ids, "choose every branch or at least one branch"),
       else: validate_length(changeset, :location_ids, max: 200)
  end
end
