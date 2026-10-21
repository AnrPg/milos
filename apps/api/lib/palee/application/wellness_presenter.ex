defmodule Palee.Application.WellnessPresenter do
  @moduledoc """
  Plain shapes of wellness entries and cravings (ADR-159), shared by the
  Ευεξία endpoints and the journal feed so both say the same thing.
  """

  alias Palee.Wellness.{Craving, Entry}

  def entry(%Entry{} = entry) do
    %{
      id: entry.id,
      kind: entry.kind,
      occurred_at: entry.occurred_at,
      occurred_tz: entry.occurred_tz,
      occurred_on: entry.occurred_on,
      value: entry.value,
      source: entry.source,
      corrected: not is_nil(entry.corrected_at),
      organization_id: entry.organization_id,
      journal_visibility: entry.journal_visibility,
      inserted_at: entry.inserted_at,
      updated_at: entry.updated_at
    }
  end

  def craving(%Craving{} = craving) do
    %{
      id: craving.id,
      occurred_at: craving.occurred_at,
      occurred_tz: craving.occurred_tz,
      occurred_on: craving.occurred_on,
      intensity: craving.intensity,
      triggers: craving.triggers,
      outcome: craving.outcome,
      outcome_at: craving.outcome_at,
      note: craving.note,
      support_requested_at: craving.support_requested_at,
      follow_up_at: craving.follow_up_at,
      organization_id: craving.organization_id,
      journal_visibility: craving.journal_visibility,
      inserted_at: craving.inserted_at,
      updated_at: craving.updated_at
    }
  end
end
