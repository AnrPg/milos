defmodule MilosTraining.Identity.User do
  use Ecto.Schema
  import Ecto.Changeset
  alias MilosTraining.Identity.RegistrationPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :nickname, :string
    field :password, :string, virtual: true
    field :password_hash, :string
    field :role, Ecto.Enum, values: RegistrationPolicy.roles()
    field :leaderboard_opt_in, :boolean, default: false

    timestamps()
  end

  def registration_changeset(user \\ %__MODULE__{}, params) do
    user
    |> cast(params, [:nickname, :password, :role, :leaderboard_opt_in])
    |> update_change(:nickname, &RegistrationPolicy.normalize_nickname/1)
    |> validate_required([:nickname, :password, :role])
    |> validate_length(:nickname, min: 3, max: 30)
    |> validate_format(:nickname, ~r/^[a-zA-Z0-9_]+$/)
    |> validate_inclusion(:role, RegistrationPolicy.self_register_roles())
    |> validate_length(:password, min: 8)
    |> unique_constraint(:nickname)
  end

  def role_changeset(user, params) do
    user
    |> cast(params, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, RegistrationPolicy.roles())
  end
end
