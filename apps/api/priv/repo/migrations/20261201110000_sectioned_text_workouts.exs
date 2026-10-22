defmodule Palee.Repo.Migrations.SectionedTextWorkouts do
  @moduledoc """
  ADR-180: a workout written without the assistant is a list of text
  sections, each with its own timer (`authoring_mode = 'sectioned_text'`).
  A section keeps its rich text (plain and TipTap JSON, as the workout itself
  does for free text) and the timer preset the coach chose for it (the same
  shape as the free-text and class timer presets). Additive: existing rows
  keep nulls, and the mode check only gains a value.
  """

  use Ecto.Migration

  def up do
    alter table(:workout_sections) do
      add :free_text_body, :text
      add :free_text_document, :map
      add :timer_preset, :map
    end

    replace_mode_check(~w(structured quick_text free_text sectioned_text))
  end

  def down do
    execute("""
    UPDATE master_workouts SET authoring_mode = 'free_text'
    WHERE authoring_mode = 'sectioned_text'
    """)

    replace_mode_check(~w(structured quick_text free_text))

    alter table(:workout_sections) do
      remove :free_text_body
      remove :free_text_document
      remove :timer_preset
    end
  end

  defp replace_mode_check(modes) do
    execute("ALTER TABLE master_workouts DROP CONSTRAINT master_workouts_authoring_mode_check")

    create constraint(:master_workouts, :master_workouts_authoring_mode_check,
             check: "authoring_mode IN (#{Enum.map_join(modes, ", ", &"'#{&1}'")})"
           )
  end
end
