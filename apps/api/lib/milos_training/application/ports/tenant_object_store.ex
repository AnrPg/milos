defmodule MilosTraining.Application.Ports.TenantObjectStore do
  @moduledoc """
  Object-storage operations needed for the reviewed tenant export/purge
  (ADR-117). `bucket` is a logical name, never a raw bucket string, so callers
  cannot address arbitrary buckets.
  """

  @type bucket :: :documents | :avatars | :branding | :media_public | :media_private
  @type object :: %{key: String.t(), size: non_neg_integer()}
  @type probe :: %{head: binary(), byte_size: non_neg_integer() | nil}

  @callback put_object(bucket(), String.t(), binary(), String.t()) :: :ok | {:error, term()}
  @callback list_objects(bucket(), String.t()) :: {:ok, [object()]} | {:error, term()}
  @callback delete_objects(bucket(), [String.t()]) ::
              {:ok, non_neg_integer()} | {:error, term()}
  @callback presigned_object_url(bucket(), String.t()) :: {:ok, String.t()} | {:error, term()}

  # ADR-121 tenant logo uploads (`:branding` lives in the public media bucket).
  @doc "Presigned PUT constrained to `content_type`; returns url and required headers."
  @callback presigned_upload(bucket(), String.t(), String.t()) ::
              {:ok, %{url: String.t(), headers: %{String.t() => String.t()}}}
              | {:error, term()}
  @doc "Leading `bytes` of an object plus its total size, without downloading it all."
  @callback probe_object(bucket(), String.t(), pos_integer()) ::
              {:ok, probe()} | {:error, :not_found} | {:error, term()}
  @doc "Streams a whole object to a local file (ADR-157 media processing)."
  @callback download_object(bucket(), String.t(), Path.t()) ::
              :ok | {:error, :not_found} | {:error, term()}
  @doc "Stable public URL of an object in a publicly readable bucket."
  @callback public_object_url(bucket(), String.t()) :: {:ok, String.t()} | {:error, term()}
end
