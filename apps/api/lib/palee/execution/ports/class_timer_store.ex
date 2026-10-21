defmodule Palee.Execution.Ports.ClassTimerStore do
  @callback get_class_timer(map(), binary()) :: map() | nil
  @callback save_class_timer(map(), binary(), map(), pos_integer() | nil) ::
              {:ok, map()} | {:error, :stale_class_timer} | {:error, Ecto.Changeset.t()}
end
