defmodule Palee.Scheduling.Domain.ClassWorkoutReadiness do
  @moduledoc """
  Whether a class has its WOD, and what that means (ADR-176).

  Staff may create a class before its WOD exists and link one later:

    * A **standalone** class without a WOD is a draft. Members never see it
      and nobody can book it until a WOD is linked; staff see it as
      incomplete.
    * A **series** occurrence may stay without a WOD (series are programmed
      day by day). It stays published, and from 00:00 on its own day it
      shows as incomplete to staff.

  Every class still missing its WOD on its day alerts the staff who can fix
  it: at 07:00 that morning and one hour before it starts. Days and 07:00
  are read in the gym's own time zone (`Organizations.organization_timezone/1`),
  passed in by the caller. A sweep picks the latest alert moment that has passed, so a missed
  sweep never sends a stale morning alert after the hour-before one.
  """

  @morning ~T[07:00:00]
  @hour_before_minutes 60

  @type slot :: %{
          required(:master_workout_id) => term(),
          required(:class_series_id) => term(),
          required(:scheduled_at) => DateTime.t(),
          optional(atom()) => term()
        }

  @type workout_status :: :linked | :awaiting | :missing
  @type alert_kind :: :morning | :hour_before

  @doc "The class has a WOD."
  def linked?(slot), do: not is_nil(Map.get(slot, :master_workout_id))

  @doc """
  Members can see and book the class: it has a WOD or belongs to a series. A
  projection that does not carry the WOD at all is not judged a draft.
  """
  def published?(slot) do
    case {Map.fetch(slot, :master_workout_id), Map.get(slot, :class_series_id)} do
      {{:ok, nil}, nil} -> false
      _linked_or_series -> true
    end
  end

  @doc "`:ok`, or `{:error, :class_not_published}` for a draft class."
  def ensure_published(slot),
    do: if(published?(slot), do: :ok, else: {:error, :class_not_published})

  @doc """
  `:linked` with a WOD; `:missing` (the incomplete badge) for a draft or for
  a series occurrence from 00:00 on its day; `:awaiting` for a series
  occurrence on an earlier day.
  """
  @spec workout_status(slot(), DateTime.t(), String.t()) :: workout_status()
  def workout_status(slot, %DateTime{} = now, zone) do
    cond do
      linked?(slot) -> :linked
      not published?(slot) -> :missing
      Date.compare(local_date(now, zone), local_date(slot.scheduled_at, zone)) != :lt -> :missing
      true -> :awaiting
    end
  end

  @doc """
  When staff hear about a missing WOD, ascending: 07:00 on the class's day
  (only while that is still before the hour-before alert) and one hour
  before it starts.
  """
  @spec alert_moments(slot(), String.t()) :: [{alert_kind(), DateTime.t()}]
  def alert_moments(%{scheduled_at: %DateTime{} = starts_at}, zone) do
    hour_before = DateTime.add(starts_at, -@hour_before_minutes, :minute)

    morning =
      case DateTime.new(local_date(starts_at, zone), @morning, zone) do
        {:ok, at} -> DateTime.shift_zone!(at, "Etc/UTC")
        {:ambiguous, first, _second} -> DateTime.shift_zone!(first, "Etc/UTC")
        {:gap, _before, after_gap} -> DateTime.shift_zone!(after_gap, "Etc/UTC")
        {:error, _reason} -> nil
      end

    if morning && DateTime.compare(morning, hour_before) == :lt,
      do: [{:morning, morning}, {:hour_before, hour_before}],
      else: [{:hour_before, hour_before}]
  end

  @doc """
  The alert a sweep at `now` owes for a class without a WOD: the latest
  moment already passed, while the class has not started. Nil otherwise.
  """
  @spec alert_due(slot(), DateTime.t(), String.t()) :: {alert_kind(), DateTime.t()} | nil
  def alert_due(slot, %DateTime{} = now, zone) do
    if linked?(slot) or DateTime.compare(now, slot.scheduled_at) != :lt do
      nil
    else
      slot
      |> alert_moments(zone)
      |> Enum.filter(fn {_kind, at} -> DateTime.compare(at, now) != :gt end)
      |> List.last()
    end
  end

  @doc """
  How far ahead a sweep must look: a class can owe its morning alert up to a
  day before it starts.
  """
  def alert_horizon_hours, do: 24

  defp local_date(%DateTime{} = at, zone) do
    case DateTime.shift_zone(at, zone) do
      {:ok, local} -> DateTime.to_date(local)
      {:error, _reason} -> DateTime.to_date(at)
    end
  end
end
