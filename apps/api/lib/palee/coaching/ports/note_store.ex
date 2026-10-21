defmodule Palee.Coaching.Ports.NoteStore do
  @moduledoc "Persistence port for private coach notes and their reads (ADR-101)."

  @callback create(map(), map()) :: {:ok, map()} | {:error, term()}
  @callback get(map(), binary()) :: map() | nil
  @callback update(map(), binary(), map()) :: {:ok, map()} | {:error, term()}
  @callback delete(map(), binary()) :: :ok | {:error, term()}
  @callback list_for_client(map(), binary()) :: [map()]
  @callback record_reads(map(), [binary()], binary(), DateTime.t()) :: :ok
  @callback list_reads(map(), binary()) :: [map()]
end
