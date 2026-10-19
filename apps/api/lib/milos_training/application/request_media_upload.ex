defmodule MilosTraining.Application.RequestMediaUpload do
  @moduledoc """
  ADR-148: reserves a media row and issues a presigned PUT for it. The
  browser uploads straight to object storage, then calls
  `CompleteMediaUpload` with the returned `media_id`. Who may upload which
  purpose is decided by the caller's use case (`authorize` below).
  """

  alias MilosTraining.Application.MediaStorage
  alias MilosTraining.{Media, Organizations}

  @expires_in 900

  def call(context, purpose, params) when is_map(params) do
    content_type = params[:content_type] || params["content_type"]
    byte_size = params[:byte_size] || params["byte_size"]
    id = Ecto.UUID.generate()

    with :ok <- authorize(context, purpose),
         {:ok, allocation} <- Media.allocate(purpose, content_type, byte_size, id),
         owner = MediaStorage.owner(context, allocation.scope),
         key = MediaStorage.object_key(owner, allocation.relative_key),
         {:ok, upload} <-
           MediaStorage.presigned_upload(owner, allocation.bucket, key, content_type),
         {:ok, media} <-
           Media.create(context, allocation.scope, %{
             id: id,
             purpose: purpose,
             object_key: key,
             content_type: content_type
           }) do
      {:ok,
       %{
         media_id: media.id,
         upload_url: upload.url,
         required_headers: upload.headers,
         expires_in: @expires_in,
         max_bytes: allocation.max_bytes
       }}
    end
  end

  # Box photos speak for the gym: staff who manage its settings.
  defp authorize(context, "box_photo") do
    if Organizations.can?(context, :manage_settings),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp authorize(_context, purpose) do
    if purpose in Media.purposes(),
      do: {:error, :forbidden},
      else: {:error, :invalid_media_purpose}
  end
end
