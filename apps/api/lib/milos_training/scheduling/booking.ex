defmodule MilosTraining.Scheduling.Booking do
  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Scheduling.ScheduledClass

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @statuses [:pending, :approved, :rejected, :cancelled]

  schema "bookings" do
    belongs_to :scheduled_class, ScheduledClass
    field :user_id, :binary_id
    field :status, Ecto.Enum, values: @statuses
    field :admin_message, :string
    field :timeout_job_id, :integer

    timestamps()
  end

  def create_changeset(booking \\ %__MODULE__{}, params) do
    booking
    |> cast(params, [:scheduled_class_id, :user_id, :status])
    |> validate_required([:scheduled_class_id, :user_id, :status])
    |> foreign_key_constraint(:scheduled_class_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id, name: :bookings_slot_user_index)
  end

  def resolution_changeset(booking, params) do
    booking
    |> cast(params, [:status, :admin_message])
    |> validate_required([:status])
    |> validate_inclusion(:status, [:approved, :rejected])
  end

  def timeout_job_changeset(booking, job_id) do
    booking
    |> change(timeout_job_id: job_id)
  end

  def statuses, do: @statuses
end
