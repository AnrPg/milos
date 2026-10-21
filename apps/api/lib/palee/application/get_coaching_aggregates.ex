defmodule Palee.Application.GetCoachingAggregates do
  alias Palee.Coaching

  def call, do: {:ok, Coaching.get_aggregates()}
end
