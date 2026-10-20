defmodule MilosTraining.Wellness.Preferences do
  @moduledoc "The member's wellness targets and hidden items (ADR-159 §4)."

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Wellness.Domain.PreferencesPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "wellness_preferences" do
    field(:user_id, :binary_id)
    field(:water_goal_ml, :integer, default: 2_000)
    field(:glass_ml, :integer, default: 250)
    field(:sleep_goal_minutes, :integer, default: 420)
    field(:hidden_items, {:array, :string}, default: [])
    field(:item_order, {:array, :string}, default: [])
    field(:water_reminder, :boolean, default: false)
    field(:water_reminded_on, :date)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(preferences, attrs) do
    preferences
    |> cast(attrs, [
      :user_id,
      :water_goal_ml,
      :glass_ml,
      :sleep_goal_minutes,
      :hidden_items,
      :item_order,
      :water_reminder
    ])
    |> validate_required([:user_id, :water_goal_ml, :glass_ml, :sleep_goal_minutes])
    |> validate_number(:water_goal_ml,
      greater_than_or_equal_to: 250,
      less_than_or_equal_to: 8_000
    )
    |> validate_number(:glass_ml, greater_than_or_equal_to: 50, less_than_or_equal_to: 2_000)
    |> validate_number(:sleep_goal_minutes,
      greater_than_or_equal_to: 240,
      less_than_or_equal_to: 720
    )
    |> validate_subset(:hidden_items, PreferencesPolicy.items())
    |> update_change(:hidden_items, &Enum.uniq/1)
    |> validate_subset(:item_order, PreferencesPolicy.items())
    |> update_change(:item_order, &Enum.uniq/1)
    |> unique_constraint(:user_id)
  end
end
