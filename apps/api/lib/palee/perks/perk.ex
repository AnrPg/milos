defmodule Palee.Perks.Perk do
  @moduledoc """
  A partner perk (ADR-191): a deal a business's clients use at a partner
  business. Its lifecycle and audience rules are `Domain.PerkRules`; the
  database repeats the invariants as check constraints.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Finance.PromotionCode
  alias Palee.Perks.Domain.PerkRules

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @editable ~w(partner_name partner_url partner_address logo_media_id benefit_type benefit_value
               benefit_text currency redemption_method shared_code terms valid_from valid_until
               max_claims max_claims_per_member audience package_ids all_locations
               location_ids)a

  @type t :: %__MODULE__{}

  schema "perks" do
    field :organization_id, :binary_id, read_after_writes: true
    field :partner_name, :string
    field :partner_url, :string
    field :partner_address, :string
    field :logo_media_id, :binary_id
    field :benefit_type, :string
    field :benefit_value, :integer
    field :benefit_text, :string
    field :currency, :string, default: "EUR"
    field :redemption_method, :string
    field :shared_code, :string
    field :terms, :string
    field :valid_from, :date
    field :valid_until, :date
    field :max_claims, :integer
    field :max_claims_per_member, :integer, default: 1
    field :audience, :string, default: "all_clients"
    field :package_ids, {:array, :binary_id}, default: []
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
    |> cast(attrs, [:updated_by_id | @editable])
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
    |> update_change(:shared_code, &PromotionCode.normalize_code/1)
    |> update_change(:currency, &upcase/1)
    |> validate_required([:partner_name, :benefit_type, :redemption_method])
    |> validate_length(:partner_name, min: 1, max: 120)
    |> validate_length(:partner_url, max: 500)
    |> validate_length(:partner_address, max: 300)
    |> validate_length(:benefit_text, max: 200)
    |> validate_length(:terms, max: 4_000)
    |> validate_length(:shared_code, min: 1, max: 64)
    |> validate_format(:currency, ~r/^[A-Z]{3}$/)
    |> validate_format(:partner_url, ~r/^https?:\/\/[^\s]+$/i, message: "must be an http(s) link")
    |> validate_inclusion(:benefit_type, PerkRules.benefit_types())
    |> validate_inclusion(:redemption_method, PerkRules.methods())
    |> validate_inclusion(:audience, PerkRules.audiences())
    |> validate_number(:max_claims, greater_than: 0)
    |> validate_number(:max_claims_per_member, greater_than: 0, less_than_or_equal_to: 1_000)
    |> validate_benefit()
    |> validate_method()
    |> validate_audience()
    |> validate_branches()
    |> validate_window()
    |> check_constraint(:benefit_value, name: :perks_benefit_check)
    |> check_constraint(:shared_code, name: :perks_redemption_method_check)
    |> check_constraint(:package_ids, name: :perks_audience_check)
    |> check_constraint(:valid_until, name: :perks_window_check)
    |> check_constraint(:max_claims, name: :perks_claims_cap_check)
    |> check_constraint(:location_ids, name: :perks_location_scope_check)
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value
  defp upcase(value) when is_binary(value), do: String.upcase(value)
  defp upcase(value), do: value

  defp validate_benefit(changeset) do
    case get_field(changeset, :benefit_type) do
      "percent" ->
        changeset
        |> validate_required([:benefit_value])
        |> validate_number(:benefit_value, greater_than: 0, less_than_or_equal_to: 100)

      "fixed_amount" ->
        changeset
        |> validate_required([:benefit_value])
        |> validate_number(:benefit_value, greater_than: 0, less_than_or_equal_to: 10_000_000)

      "free_text" ->
        validate_required(changeset, [:benefit_text])

      _other ->
        changeset
    end
  end

  defp validate_method(changeset) do
    case get_field(changeset, :redemption_method) do
      "shared_code" -> validate_required(changeset, [:shared_code])
      method when method in ["unique_code", "qr"] -> put_change(changeset, :shared_code, nil)
      _other -> changeset
    end
  end

  defp validate_audience(changeset) do
    ids = get_field(changeset, :package_ids) || []

    case get_field(changeset, :audience) do
      "packages" when ids == [] ->
        add_error(changeset, :package_ids, "choose at least one package")

      "all_clients" ->
        put_change(changeset, :package_ids, [])

      _other ->
        changeset
    end
    |> validate_length(:package_ids, max: 200)
  end

  defp validate_branches(changeset) do
    if get_field(changeset, :all_locations) == false and
         (get_field(changeset, :location_ids) || []) == [],
       do: add_error(changeset, :location_ids, "choose every branch or at least one branch"),
       else: validate_length(changeset, :location_ids, max: 200)
  end

  defp validate_window(changeset) do
    from = get_field(changeset, :valid_from)
    until = get_field(changeset, :valid_until)

    if from && until && Date.compare(until, from) == :lt,
      do: add_error(changeset, :valid_until, "must be on or after the start date"),
      else: changeset
  end
end
