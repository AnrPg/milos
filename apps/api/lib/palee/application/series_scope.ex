defmodule Palee.Application.SeriesScope do
  @moduledoc """
  The classes an operation on one class reaches (ADR-200): only that class, or
  by `series_scope` (`all`: this class and the ones after it / `range`) and
  `every` the other upcoming classes of its series. Edits and pause / cancel / delete share it, so they always reach
  the same classes. The rules are `Palee.Scheduling.Domain.SeriesEdit`.
  """

  alias Palee.Scheduling
  alias Palee.Scheduling.Domain.SeriesEdit

  @keys [:series_scope, :range_from, :range_to, :every]

  @doc "The request keys that only choose the scope."
  def keys, do: @keys ++ Enum.map(@keys, &Atom.to_string/1)

  @doc "Reads the scope and the `every` step from the request."
  def read(params) do
    with {:ok, scope} <- SeriesEdit.scope(params),
         {:ok, every} <- SeriesEdit.every(params),
         do: {:ok, {scope, every}}
  end

  @doc """
  The class itself, its series (or nil) and the other classes reached, in
  date order. A range past the classes created so far creates them first.
  """
  def resolve(context, slot_id, {scope, every}) do
    case Scheduling.get_slot(context, slot_id) do
      nil ->
        {:error, :not_found}

      %{class_series_id: series_id} = current when is_binary(series_id) and scope != :this ->
        with %{} = series <-
               Scheduling.get_class_series(context, series_id) || {:error, :not_found},
             :ok <- materialize_through(context, series, SeriesEdit.last_date(scope)) do
          now = DateTime.utc_now()

          targets =
            context
            |> Scheduling.list_series_slots(series.id, now)
            |> SeriesEdit.targets(scope, series.timezone, current, now)
            |> SeriesEdit.every_nth(current.scheduled_at, every)

          {:ok, %{current: current, series: series, targets: targets, scope: scope, every: every}}
        end

      current ->
        {:ok, %{current: current, series: nil, targets: [], scope: :this, every: 1}}
    end
  end

  @doc """
  The classes a pause, cancel or delete acts on, in date order: the class
  itself when its date is in the scope, then the others reached.
  """
  def reached(%{current: current, series: %{timezone: timezone}, scope: scope, targets: targets}) do
    if SeriesEdit.reaches_own_class?(scope, timezone, current.scheduled_at),
      do: Enum.sort_by([current | targets], & &1.scheduled_at, DateTime),
      else: targets
  end

  def reached(%{current: current}), do: [current]

  @doc "Whether the operation reaches every class of the series from this one on."
  def whole_series?(%{series: %{}, scope: :all, every: 1}), do: true
  def whole_series?(_resolved), do: false

  defp materialize_through(_context, _series, nil), do: :ok

  defp materialize_through(context, %{status: "active"} = series, %Date{} = last) do
    if Date.after?(last, series.materialized_through) do
      case Scheduling.extend_class_series(context, series.id, last) do
        {:ok, _series} -> :ok
        error -> error
      end
    else
      :ok
    end
  end

  defp materialize_through(_context, _series, _last), do: :ok
end
