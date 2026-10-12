defmodule MilosTraining.Application.Ports.TenantObjectStore do
  @moduledoc """
  Object-storage operations needed for the reviewed tenant export/purge
  (ADR-099). `bucket` is a logical name, never a raw bucket string, so callers
  cannot address arbitrary buckets.
  """

  @type bucket :: :documents | :avatars
  @type object :: %{key: String.t(), size: non_neg_integer()}

  @callback put_object(bucket(), String.t(), binary(), String.t()) :: :ok | {:error, term()}
  @callback list_objects(bucket(), String.t()) :: {:ok, [object()]} | {:error, term()}
  @callback delete_objects(bucket(), [String.t()]) ::
              {:ok, non_neg_integer()} | {:error, term()}
  @callback presigned_object_url(bucket(), String.t()) :: {:ok, String.t()} | {:error, term()}
end
