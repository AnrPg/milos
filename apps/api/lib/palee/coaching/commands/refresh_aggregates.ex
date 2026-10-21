defmodule Palee.Coaching.Commands.RefreshAggregates do
  alias Palee.Coaching.CoachingStore

  def call, do: CoachingStore.refresh_aggregates()
end
