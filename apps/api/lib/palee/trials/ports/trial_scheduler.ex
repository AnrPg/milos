defmodule Palee.Trials.Ports.TrialScheduler do
  @moduledoc """
  Schedules a trial's timed steps (ADR-144): the reminder before the class,
  the expiry of an unanswered ask at class time, and the follow-up the day
  after. Each step re-reads the trial when it fires and does nothing if the
  trial has moved on, so scheduling is fire-and-forget.
  """

  @type step :: :reminder | :expire | :follow_up

  @callback schedule(
              organization_id :: binary(),
              trial_id :: binary(),
              [{step(), DateTime.t()}]
            ) :: :ok
end
