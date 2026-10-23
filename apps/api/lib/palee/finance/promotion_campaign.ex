defmodule Palee.Finance.PromotionCampaign do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "promotion_campaigns" do
    field :organization_id, :binary_id, read_after_writes: true
    field :name, :string
    field :description, :string
    field :starts_on, :date
    field :ends_on, :date
    field :active, :boolean, default: true
    field :params, :map, default: %{}
    # ADR-186 §8: «Ισχύει για» — every branch (future ones too) or these.
    field :all_locations, :boolean, default: true
    field :location_ids, {:array, :binary_id}, default: []

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(campaign \\ %__MODULE__{}, params) do
    campaign
    |> cast(params, [
      :name,
      :description,
      :starts_on,
      :ends_on,
      :active,
      :params,
      :all_locations,
      :location_ids
    ])
    |> validate_required([:name])
    |> validate_date_window()
    |> check_constraint(:location_ids, name: :promotion_campaigns_location_scope_check)
  end

  defp validate_date_window(changeset) do
    starts_on = get_field(changeset, :starts_on)
    ends_on = get_field(changeset, :ends_on)

    if starts_on && ends_on && Date.compare(ends_on, starts_on) == :lt do
      add_error(changeset, :ends_on, "must be on or after the start date")
    else
      changeset
    end
  end
end
