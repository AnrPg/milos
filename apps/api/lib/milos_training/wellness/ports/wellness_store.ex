defmodule MilosTraining.Wellness.Ports.WellnessStore do
  @moduledoc """
  Persistence port of the Wellness context (ADR-159). Every call runs inside
  the caller's RepoContext (the member's personal session, or a coach's
  tenant session for reads), so row security decides what is visible.
  """

  alias MilosTraining.Wellness.{Craving, Entry, Preferences}

  @type id :: Ecto.UUID.t()
  @type result(t) :: {:ok, t} | {:error, term()}

  @callback insert_entry(map()) :: result(Entry.t())
  @callback upsert_device_entry(map()) :: result(Entry.t())
  @callback get_entry(id(), id()) :: Entry.t() | nil
  @callback change_entry(Entry.t(), map(), DateTime.t()) :: result(Entry.t())
  @callback set_entry_visibility(Entry.t(), String.t()) :: result(Entry.t())
  @callback delete_entry(Entry.t(), DateTime.t()) :: result(Entry.t())
  @callback list_entries(id(), Date.t(), Date.t()) :: [Entry.t()]

  @callback list_day_items(id(), term(), pos_integer(), term()) :: [map()]
  @callback list_craving_items(id(), term(), pos_integer(), term()) :: [Craving.t()]

  @callback insert_craving(map()) :: result(Craving.t())
  @callback get_craving(id(), id()) :: Craving.t() | nil
  @callback change_craving(Craving.t(), map()) :: result(Craving.t())
  @callback set_craving_visibility(Craving.t(), String.t()) :: result(Craving.t())
  @callback delete_craving(Craving.t(), DateTime.t()) :: result(Craving.t())
  @callback list_cravings(id(), Date.t(), Date.t()) :: [Craving.t()]
  @callback craving_follow_ups_due(DateTime.t(), pos_integer()) :: [{id(), id()}]
  @callback mark_followed_up(Craving.t(), DateTime.t()) :: result(Craving.t())

  @callback get_preferences(id()) :: Preferences.t() | nil
  @callback put_preferences(id(), map()) :: result(Preferences.t())
  @callback water_reminders_due(DateTime.t(), pos_integer()) :: [{id(), Date.t()}]
  @callback mark_water_reminded(id(), Date.t()) :: :ok

  @callback erase(id(), [String.t()], DateTime.t()) :: %{String.t() => non_neg_integer()}
  @callback transaction((-> term())) :: {:ok, term()} | {:error, term()}
end
