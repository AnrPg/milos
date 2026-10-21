defmodule Palee.Devices.DailyStat do
  @moduledoc "A day's resting heart rate (ADR-161) and steps (ADR-172) from a device, for Πρόοδος."

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
    field :steps, :integer

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(stat \\ %__MODULE__{}, attrs) do
    stat
    |> cast(attrs, [:user_id, :on, :source, :resting_heart_rate, :steps])
    |> validate_required([:user_id, :on, :source])
    |> unique_constraint([:user_id, :on, :source])
    |> check_constraint(:resting_heart_rate, name: :daily_stats_resting_check)
    |> check_constraint(:steps, name: :daily_stats_steps_check)
  end
end
