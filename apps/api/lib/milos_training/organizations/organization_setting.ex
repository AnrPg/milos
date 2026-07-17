defmodule MilosTraining.Organizations.OrganizationSetting do
  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Organizations.Domain.InvitationPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organization_settings" do
    field :organization_id, :binary_id
    field :timezone, :string, default: "UTC"
    field :default_locale, :string, default: "en"
    field :invitation_lifetime_seconds, :integer, default: 604_800
    field :settings, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(setting \\ %__MODULE__{}, params) do
    setting
    |> cast(params, [
      :organization_id,
      :timezone,
      :default_locale,
      :invitation_lifetime_seconds,
      :settings
    ])
    |> validate_required([
      :organization_id,
      :timezone,
      :default_locale,
      :invitation_lifetime_seconds,
      :settings
    ])
    |> validate_length(:timezone, min: 1, max: 100)
    |> validate_length(:default_locale, min: 2, max: 20)
    |> validate_change(:invitation_lifetime_seconds, fn field, seconds ->
      if InvitationPolicy.valid_lifetime?(seconds),
        do: [],
        else: [{field, "must be between 300 and 604800 seconds"}]
    end)
    |> unique_constraint(:organization_id)
    |> foreign_key_constraint(:organization_id)
  end
end
