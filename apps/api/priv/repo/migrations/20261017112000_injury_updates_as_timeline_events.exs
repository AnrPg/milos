defmodule MilosTraining.Repo.Migrations.InjuryUpdatesAsTimelineEvents do
  @moduledoc """
  ADR-140 §3: an injury's progress is a timeline of `reported`, `updated`,
  `marked_healed` and `reopened` events. `note_added` had no producer; any
  row of it becomes a text-only `updated` event.
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE injury_status_events
    SET event_type = 'updated',
        payload = jsonb_build_object('note', payload->>'note', 'changes', '[]'::jsonb)
    WHERE event_type = 'note_added'
    """)

    create constraint(:injury_status_events, :injury_status_events_event_type_check,
             check: "event_type IN ('reported', 'updated', 'marked_healed', 'reopened')"
           )
  end

  def down do
    drop constraint(:injury_status_events, :injury_status_events_event_type_check)
  end
end
