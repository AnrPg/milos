defmodule MilosTraining.Repo.Migrations.AddFeltPromptWithoutGoalsToBodySettings do
  @moduledoc """
  ADR-163: a member can switch off the «Τι ένιωσες;» step for workouts
  without goals (on by default). It lives with the member's other journal
  preferences in `body_settings`, whose owner-only policy already covers it.
  """

  use Ecto.Migration

  def change do
    alter table(:body_settings) do
      add :felt_prompt_without_goals, :boolean, null: false, default: true
    end
  end
end
