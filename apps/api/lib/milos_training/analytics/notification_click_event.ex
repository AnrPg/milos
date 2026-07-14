defmodule MilosTraining.Analytics.NotificationClickEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notification_click_events" do
    field :notification_id, :binary_id
    field :user_id, :binary_id
    field :url, :string
    field :clicked_at, :utc_datetime_usec
    field :metadata, :map, default: %{}
  end

  def changeset(click_event \\ %__MODULE__{}, params) do
    click_event
    |> cast(params, [:notification_id, :user_id, :url, :clicked_at, :metadata])
    |> validate_required([:notification_id, :user_id, :clicked_at])
    |> foreign_key_constraint(:notification_id)
    |> foreign_key_constraint(:user_id)
  end
end
