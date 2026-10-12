defmodule MilosTraining.Application.EntitlementClassTypeNames do
  @moduledoc """
  Adds class type names to an effective entitlement read model so clients can
  label per-class-type allowances (ADR-096) without Finance reading Scheduling.
  """

  alias MilosTraining.Scheduling

  def put(_context, nil), do: nil

  def put(%{organization_id: _} = context, entitlement) when is_map(entitlement) do
    names =
      context
      |> Scheduling.list_class_types(include_archived: true)
      |> Map.new(&{&1.id, &1.name})

    Map.put(entitlement, :class_type_names, names)
  end

  def put(_context, entitlement), do: entitlement
end
