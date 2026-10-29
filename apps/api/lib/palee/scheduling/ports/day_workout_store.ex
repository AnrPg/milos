defmodule Palee.Scheduling.Ports.DayWorkoutStore do
  @moduledoc "Storage of day WODs and the class facts their inheritance reads (ADR-230)."

  alias Palee.Organizations.TenantContext

  @type rule :: %{
          id: Ecto.UUID.t(),
          local_date: Date.t(),
          class_type_id: Ecto.UUID.t() | nil,
          location_id: Ecto.UUID.t() | nil,
          master_workout_id: Ecto.UUID.t(),
          set_by_id: Ecto.UUID.t() | nil
        }

  @type class_change ::
          {Ecto.UUID.t(),
           {:inherit, %{id: Ecto.UUID.t(), master_workout_id: Ecto.UUID.t()}} | :clear | :detach}

  @callback transaction(TenantContext.t(), (-> {:ok, term()} | {:error, term()})) ::
              {:ok, term()} | {:error, term()}
  @callback list_rules(TenantContext.t(), Date.t(), Date.t()) :: [rule()]
  @callback get_rule(TenantContext.t(), Ecto.UUID.t()) :: rule() | nil
  @callback put_rule(TenantContext.t(), map()) :: {:ok, rule()} | {:error, Ecto.Changeset.t()}
  @callback delete_rule(TenantContext.t(), Ecto.UUID.t()) :: {:ok, rule()} | {:error, :not_found}
  @callback list_classes(TenantContext.t(), DateTime.t(), DateTime.t()) :: [map()]
  @callback apply_changes(TenantContext.t(), [class_change()]) ::
              {:ok, [Ecto.UUID.t()]} | {:error, term()}
end
