defmodule MilosTraining.Organizations.Vendor do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "vendors" do
    field :user_id, :binary_id
    field :status, Ecto.Enum, values: [:active, :revoked], default: :active
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t(),
          status: :active | :revoked,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  def changeset(vendor \\ %__MODULE__{}, params) do
    vendor
    |> cast(params, [:user_id, :status])
    |> validate_required([:user_id, :status])
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end
end
