defmodule Palee.Body.Settings do
  @moduledoc "A person's body settings (ADR-158); see `SettingsPolicy`."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "body_settings" do
    field :user_id, :binary_id
    field :units, :string, default: "metric"
    field :weight_display, :string, default: "number"
    field :journal_sections, :map
    field :measure_reminder_weeks, :integer
    field :reminder_anchor_at, :utc_datetime_usec
    field :last_reminded_at, :utc_datetime_usec
    field :default_visibility, :string, default: "private"
    field :blur_photos, :boolean, default: true
    field :compare_mode, :string, default: "slider"
    # ADR-163: offer «Τι ένιωσες;» after workouts without goals.
    field :felt_prompt_without_goals, :boolean, default: true

    timestamps(type: :utc_datetime_usec)
  end
end
