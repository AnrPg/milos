defmodule Palee.Repo.Migrations.ViewerAndEventTimeZones do
  @moduledoc """
  ADR-177: the two clocks a stored UTC moment is read on besides the gym's.

    * `users.time_zone` - the IANA zone the person's device last reported,
      so push texts can add "your time" when it reads a moment differently.
    * `community_events.time_zone` - an event's own zone when it happens
      away from its gym (a competition abroad); NULL means the gym's zone.
  """

  use Ecto.Migration

  def change do
    alter table(:users) do
      add :time_zone, :string, size: 100
    end

    alter table(:community_events) do
      add :time_zone, :string, size: 100
    end
  end
end
