defmodule MilosTraining.Execution.Ports.ExecutionStore do
  @callback start_execution(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback complete_execution(binary(), map()) ::
              {:ok, map()}
              | {:error, Ecto.Changeset.t()}
              | {:error, :not_found}
              | {:error, :already_completed}
  @callback complete_execution_with_job(binary(), map(), Ecto.Changeset.t()) ::
              {:ok, map()}
              | {:error, Ecto.Changeset.t()}
              | {:error, :not_found}
              | {:error, :already_completed}
  @callback update_execution(binary(), map()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback get_execution(binary()) :: map() | nil
  @callback list_executions_for_user(binary()) :: [map()]
  @callback progress_operation_applied?(binary(), binary(), binary()) :: boolean()
end
