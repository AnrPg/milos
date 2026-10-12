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
    field :brand_name, :string
    field :brand_logo_url, :string
    # ADR-103: storage key of an uploaded logo; `brand_logo_url` then holds
    # its derived public URL. Only `logo_changeset/2` writes it.
    field :brand_logo_object_key, :string
    field :brand_primary_color, :string
    field :settings, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(setting \\ %__MODULE__{}, params) do
    setting
    |> cast(params, [
      :organization_id,
      :timezone,
      :default_locale,
      :invitation_lifetime_seconds,
      :brand_name,
      :brand_logo_url,
      :brand_primary_color,
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
    |> validate_length(:brand_name, max: 120)
    |> validate_format(:brand_primary_color, ~r/^#[0-9A-Fa-f]{6}$/)
    |> validate_change(:invitation_lifetime_seconds, fn field, seconds ->
      if InvitationPolicy.valid_lifetime?(seconds),
        do: [],
        else: [{field, "must be between 300 and 604800 seconds"}]
    end)
    |> validate_change(:brand_logo_url, fn field, _url ->
      if is_nil(setting.brand_logo_object_key),
        do: [],
        else: [{field, "is managed by the uploaded logo; remove the upload first"}]
    end)
    |> unique_constraint(:organization_id)
    |> foreign_key_constraint(:organization_id)
  end

  @doc """
  ADR-103: the only write path for an uploaded logo. Sets (or clears, with
  nils) the object key and its derived public URL together.
  """
  def logo_changeset(%__MODULE__{} = setting, params) do
    setting
    |> cast(params, [:brand_logo_object_key, :brand_logo_url], empty_values: [])
    |> validate_length(:brand_logo_object_key, max: 255)
  end
end
