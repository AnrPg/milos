defmodule MilosTraining.Places.GazetteerStore do
  @moduledoc """
  Facade over the gazetteer adapter (ADR-154). The gazetteer is platform
  reference data that every session may read, so no scope is opened.
  """

  @behaviour MilosTraining.Places.Ports.GazetteerStore

  defp adapter, do: Application.fetch_env!(:milos_training, :gazetteer_store)

  @impl true
  def search(query, limit), do: adapter().search(query, limit)
  @impl true
  def get_many(ids), do: adapter().get_many(ids)
  @impl true
  def nearest(point), do: adapter().nearest(point)
end
