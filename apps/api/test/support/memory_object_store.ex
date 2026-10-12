defmodule MilosTraining.TestSupport.MemoryObjectStore do
  @moduledoc """
  In-memory `TenantObjectStore` for tests (ADR-099). Objects are keyed by
  `{bucket, key}` in a globally named Agent; tests only touch keys under their
  own freshly generated organization/user ids, so async tests do not collide.
  """

  @behaviour MilosTraining.Application.Ports.TenantObjectStore

  def start do
    case Agent.start(fn -> %{} end, name: __MODULE__) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
  end

  @impl true
  def put_object(bucket, key, body, content_type) do
    Agent.update(
      __MODULE__,
      &Map.put(&1, {bucket, key}, %{body: body, content_type: content_type})
    )
  end

  @impl true
  def list_objects(bucket, prefix) do
    {:ok,
     Agent.get(__MODULE__, fn objects ->
       for {{^bucket, key}, %{body: body}} <- objects, String.starts_with?(key, prefix) do
         %{key: key, size: byte_size(body)}
       end
       |> Enum.sort_by(& &1.key)
     end)}
  end

  @impl true
  def delete_objects(bucket, keys) do
    Agent.get_and_update(__MODULE__, fn objects ->
      present = Enum.count(keys, &Map.has_key?(objects, {bucket, &1}))
      {{:ok, present}, Map.drop(objects, Enum.map(keys, &{bucket, &1}))}
    end)
  end

  @impl true
  def presigned_object_url(bucket, key),
    do: {:ok, "https://objects.test/#{bucket}/#{key}?signature=test"}

  @impl true
  def presigned_upload(bucket, key, content_type),
    do:
      {:ok,
       %{
         url: "https://objects.test/upload/#{bucket}/#{key}?signature=test",
         headers: %{"content-type" => content_type}
       }}

  @impl true
  def probe_object(bucket, key, bytes) do
    case get(bucket, key) do
      {:ok, body} ->
        {:ok,
         %{head: binary_part(body, 0, min(bytes, byte_size(body))), byte_size: byte_size(body)}}

      :error ->
        {:error, :not_found}
    end
  end

  @impl true
  def public_object_url(bucket, key), do: {:ok, "https://media.test/#{bucket}/#{key}"}

  @doc "Raw body of a stored object, for assertions."
  def get(bucket, key) do
    Agent.get(__MODULE__, fn objects ->
      case Map.fetch(objects, {bucket, key}) do
        {:ok, %{body: body}} -> {:ok, body}
        :error -> :error
      end
    end)
  end
end
