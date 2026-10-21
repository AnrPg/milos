defmodule Palee.Application.SyncClassGroups do
  @moduledoc """
  Keeps a gym's class-slot groups (ADR-138 D7) in step with its schedule:
  Scheduling owns the recurring classes and bookings, Community owns the
  groups. Runs hourly from the club backfill job; idempotent.
  """

  alias Palee.{Community, Scheduling}

  def call(%{organization_id: _} = context, now \\ DateTime.utc_now()) do
    %{window_days: days} = Community.class_group_suggestion()

    since =
      now
      |> DateTime.add(-days * 86_400, :second)
      |> DateTime.truncate(:second)

    series = Scheduling.list_active_class_series(context)
    counts = Scheduling.series_booking_counts(context, since)
    Community.sync_class_groups(context, series, counts)
  end
end
