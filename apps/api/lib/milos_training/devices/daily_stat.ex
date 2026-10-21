defmodule MilosTraining.Devices.DailyStat do
  @moduledoc "A day's resting heart rate from a device, for Πρόοδος (ADR-161)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "daily_stats" do
    field :user_id, :binary_id
    field :on, :date
    field :source, :string
    field :resting_heart_rate, :integer

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(stat \\ %__MODULE__{}, attrs) do
    stat
    |> cast(attrs, [:user_id, :on, :source, :resting_heart_rate])
    |> validate_required([:user_id, :on, :source])
    |> unique_constraint([:user_id, :on, :source])
    |> check_constraint(:resting_heart_rate, name: :daily_stats_resting_check)
  end
end
