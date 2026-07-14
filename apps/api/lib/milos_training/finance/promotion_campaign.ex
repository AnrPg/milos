defmodule MilosTraining.Finance.PromotionCampaign do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "promotion_campaigns" do
    field :name, :string
    field :description, :string
    field :starts_on, :date
    field :ends_on, :date
    field :active, :boolean, default: true
    field :params, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(campaign \\ %__MODULE__{}, params) do
    campaign
    |> cast(params, [:name, :description, :starts_on, :ends_on, :active, :params])
    |> validate_required([:name])
    |> validate_date_window()
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
