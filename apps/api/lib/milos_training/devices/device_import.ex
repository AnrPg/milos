defmodule MilosTraining.Devices.DeviceImport do
  @moduledoc """
  One summary a provider sent (ADR-161): deduplicated per person, provider,
  kind and provider id, with a trimmed payload, what it became and how.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Devices.Domain.Catalog

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "device_imports" do
    field :connection_id, :binary_id
    field :user_id, :binary_id
    field :provider, :string
    field :kind, :string
    field :provider_id, :string
    field :payload, :map, default: %{}
    field :target_type, :string
    field :target_id, :binary_id
    field :status, :string
    field :reason, :string
    field :received_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(connection_id user_id provider kind provider_id payload target_type target_id
             status reason received_at)a

  def changeset(import \\ %__MODULE__{}, attrs) do
    import
    |> cast(attrs, @fields)
    |> validate_required([:user_id, :provider, :kind, :provider_id, :status, :received_at])
    |> validate_inclusion(:provider, Catalog.providers())
    |> validate_inclusion(:kind, Catalog.import_kinds())
    |> validate_inclusion(:status, Catalog.import_statuses())
    |> validate_inclusion(:target_type, Catalog.target_types())
    |> unique_constraint([:user_id, :provider, :kind, :provider_id])
  end
end
