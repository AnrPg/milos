defmodule Palee.Repo.Migrations.WellnessHideMacros do
  @moduledoc """
  ADR-194 (vision §8.6): the member can hide the macros of their coach's
  nutrition plan. Stored with the other wellness preferences; off by default,
  so a plan's macros stay visible until the member hides them.
  """

  use Ecto.Migration

  def change do
    alter table(:wellness_preferences) do
      add :hide_macros, :boolean, null: false, default: false
    end
  end
end
