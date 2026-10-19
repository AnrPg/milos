defmodule MilosTraining.Media.Domain.MediaPolicy do
  @moduledoc """
  What each kind of upload is (ADR-148): who owns it (a gym or a person),
  which bucket it lives in, where its key goes and how large it may be.

  Images are re-encoded in the browser before upload (which drops EXIF and
  GPS), so only JPEG and simple WebP are accepted; `ImageInspector` checks
  the stored bytes before an object becomes `ready`.
  """

  @content_types %{"image/jpeg" => "jpg", "image/webp" => "webp"}

  @purposes %{
    "box_photo" => %{scope: :tenant, bucket: :media_public, folder: "media/public/box"},
    "post_photo" => %{scope: :tenant, bucket: :media_private, folder: "media/posts"},
    "body_photo" => %{scope: :account, bucket: :media_private, folder: "media/body"}
  }

  @max_bytes 8 * 1_024 * 1_024
  @max_dimension 4_096
  @probe_bytes 128 * 1_024

  # Unattached uploads older than this are swept.
  @orphan_after_seconds 24 * 3_600

  def purposes, do: Map.keys(@purposes) |> Enum.sort()
  def tenant_purposes, do: for({p, %{scope: :tenant}} <- @purposes, do: p) |> Enum.sort()
  def account_purposes, do: for({p, %{scope: :account}} <- @purposes, do: p) |> Enum.sort()
  def content_types, do: Map.keys(@content_types) |> Enum.sort()
  def max_bytes, do: @max_bytes
  def max_dimension, do: @max_dimension
  def probe_bytes, do: @probe_bytes
  def orphan_after_seconds, do: @orphan_after_seconds

  @doc "The scope (`:tenant` | `:account`) of a purpose."
  def scope(purpose), do: purpose |> fetch!() |> Map.fetch!(:scope)

  @doc "Logical bucket of a purpose (`:media_public` | `:media_private`)."
  def bucket(purpose), do: purpose |> fetch!() |> Map.fetch!(:bucket)

  def public?(purpose), do: bucket(purpose) == :media_public

  @doc """
  Validates an upload request and returns the object key relative to its
  owner's prefix (`organizations/<id>/` or `users/<id>/`, added by storage).
  """
  def allocate(purpose, content_type, byte_size, id) when is_binary(id) do
    with {:ok, spec} <- fetch(purpose),
         {:ok, extension} <- extension(content_type),
         :ok <- validate_size(byte_size) do
      {:ok,
       %{
         scope: spec.scope,
         bucket: spec.bucket,
         relative_key: "#{spec.folder}/#{id}.#{extension}",
         content_type: content_type,
         max_bytes: @max_bytes
       }}
    end
  end

  @doc "Validates what was stored against what was requested."
  def validate_stored(expected_content_type, %{content_type: actual} = inspected, byte_size) do
    cond do
      actual != expected_content_type ->
        {:error, :media_type_mismatch}

      not is_integer(byte_size) or byte_size <= 0 ->
        {:error, :media_upload_missing}

      byte_size > @max_bytes ->
        {:error, :media_too_large}

      inspected.width > @max_dimension or inspected.height > @max_dimension ->
        {:error, :media_too_large}

      true ->
        :ok
    end
  end

  @doc "Whether an unattached upload created at `inserted_at` is an orphan at `now`."
  def orphan?(%{attached_at: nil, inserted_at: inserted_at}, %DateTime{} = now),
    do: DateTime.diff(now, inserted_at) >= @orphan_after_seconds

  def orphan?(_media, _now), do: false

  defp fetch(purpose) do
    case Map.fetch(@purposes, purpose) do
      {:ok, spec} -> {:ok, spec}
      :error -> {:error, :invalid_media_purpose}
    end
  end

  defp fetch!(purpose) do
    {:ok, spec} = fetch(purpose)
    spec
  end

  defp extension(content_type) do
    case Map.fetch(@content_types, content_type) do
      {:ok, extension} -> {:ok, extension}
      :error -> {:error, :invalid_media_type}
    end
  end

  defp validate_size(size) when is_integer(size) and size > 0 and size <= @max_bytes, do: :ok

  defp validate_size(size) when is_integer(size) and size > @max_bytes,
    do: {:error, :media_too_large}

  defp validate_size(_size), do: {:error, :invalid_media_size}
end
