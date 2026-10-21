defmodule Palee.Inventory.Domain.MachinePolicy do
  @moduledoc """
  A machine's state follows its log (ADR-104): an issue marks it as needing
  attention, `out_of_order` takes it out of use, maintenance or a repair puts
  it back to work, and retiring it is final. Issues, outages and repair calls
  alert the people who look after the inventory.
  """

  @statuses [:working, :needs_attention, :out_of_order, :retired]
  @kinds [:note, :issue, :out_of_order, :repair_requested, :maintenance, :repaired, :retired]
  @alerting [:issue, :out_of_order, :repair_requested]

  @severities [:low, :medium, :high, :safety]
  @symptoms [
    :noise,
    :not_starting,
    :broken_part,
    :leak,
    :electrical,
    :display,
    :cleanliness,
    :other
  ]

  def statuses, do: @statuses
  def severities, do: @severities
  def symptoms, do: @symptoms
  def kinds, do: @kinds
  def categories, do: [:training, :appliance]

  @doc "The status after logging `kind` on a machine in `status`."
  def next_status(:retired, _kind), do: {:error, :machine_retired}
  def next_status(_status, :retired), do: {:ok, :retired}
  def next_status(_status, :out_of_order), do: {:ok, :out_of_order}

  def next_status(:out_of_order, :issue), do: {:ok, :out_of_order}
  def next_status(_status, :issue), do: {:ok, :needs_attention}
  def next_status(_status, kind) when kind in [:maintenance, :repaired], do: {:ok, :working}
  def next_status(status, kind) when kind in [:note, :repair_requested], do: {:ok, status}
  def next_status(_status, _kind), do: {:error, :invalid_machine_event}

  # A safety issue, or one that leaves the machine unusable, takes it out of use.
  def next_status(status, :issue, %{severity: :safety}) when status != :retired,
    do: {:ok, :out_of_order}

  def next_status(status, :issue, %{usable: false}) when status != :retired,
    do: {:ok, :out_of_order}

  def next_status(status, kind, _details), do: next_status(status, kind)

  def alert?(kind), do: kind in @alerting

  @doc "Whether the machine's next service is due by `today`."
  def service_due?(%{service_interval_days: days} = machine, %Date{} = today)
      when is_integer(days) and days > 0 do
    case Map.get(machine, :last_serviced_on) || Map.get(machine, :purchased_on) do
      %Date{} = since -> Date.compare(Date.add(since, days), today) != :gt
      _never -> true
    end
  end

  def service_due?(_machine, _today), do: false

  def next_service_on(%{service_interval_days: days} = machine)
      when is_integer(days) and days > 0 do
    case Map.get(machine, :last_serviced_on) || Map.get(machine, :purchased_on) do
      %Date{} = since -> Date.add(since, days)
      _never -> nil
    end
  end

  def next_service_on(_machine), do: nil
end
