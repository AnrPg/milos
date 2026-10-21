defmodule Palee.Places.Domain.AlertPolicy do
  @moduledoc """
  Saved-filter alerts of Γύρω μου (ADR-154): opt-in per named filter, at
  most one notification per Athens day, and only when something matching
  appeared since the filter last looked. The day is claimed before
  counting, so a retried or concurrent sweep never sends twice.
  """

  alias Palee.Places.Domain.WhenWindow

  @doc "The Athens day a sweep at `now` belongs to."
  def day(%DateTime{} = now), do: WhenWindow.local_date(now, WhenWindow.default_time_zone())

  @doc "Whether a filter last checked on `checked_on` is due on `day`."
  def due?(nil, _day), do: true
  def due?(%Date{} = checked_on, %Date{} = day), do: Date.compare(checked_on, day) == :lt

  @doc "Notify only when something new matched."
  def notify?(new_total) when is_integer(new_total), do: new_total > 0

  @doc "One notification per filter and day, even if a job is retried."
  def dedupe_key(filter_id, %Date{} = day), do: "around_new_matches:#{filter_id}:#{day}"
end
