defmodule Palee.Documents.Settings do
  @moduledoc "A box's document rules: the booking gate and health certificates (ADR-252)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(block_booking_on_unsigned health_certificate_required
             block_booking_on_health_certificate health_certificate_validity_months
             health_certificate_reminder_days updated_by_id)a

  schema "document_settings" do
    field :organization_id, :binary_id
    field :block_booking_on_unsigned, :boolean, default: true
    field :health_certificate_required, :boolean, default: false
    field :block_booking_on_health_certificate, :boolean, default: false
    field :health_certificate_validity_months, :integer, default: 12
    field :health_certificate_reminder_days, :integer, default: 30
    field :updated_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def fields, do: @fields -- [:updated_by_id]

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, @fields)
    |> check_constraint(:health_certificate_validity_months, name: :document_settings_check)
  end
end
