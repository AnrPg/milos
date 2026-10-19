defmodule MilosTraining.Application.MediaUrls do
  @moduledoc """
  ADR-148: how a media item is shown to a client: its id, size and a URL
  (stable for public media, presigned and short-lived for private media).
  Callers authorize the reader first; this only builds the URL.
  """

  alias MilosTraining.Application.MediaStorage
  alias MilosTraining.Media

  def present(context, media) do
    owner = MediaStorage.owner(context, media.scope)

    url =
      case MediaStorage.read_url(owner, Media.bucket(media.purpose), media.object_key) do
        {:ok, url} -> url
        {:error, _reason} -> nil
      end

    %{
      id: media.id,
      purpose: media.purpose,
      status: media.status,
      content_type: media.content_type,
      width: media.width,
      height: media.height,
      url: url
    }
  end

  def present_all(context, media), do: Enum.map(media, &present(context, &1))
end
