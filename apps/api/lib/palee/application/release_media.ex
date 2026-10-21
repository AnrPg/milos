defmodule Palee.Application.ReleaseMedia do
  @moduledoc """
  ADR-148: deletes media a consumer no longer references (rows and objects).
  Used when a box photo is removed from the profile, a post is deleted, or
  the orphan sweep finds an upload nobody attached. A processed upload goes
  with all its renditions (ADR-157).
  """

  alias Palee.Application.MediaStorage
  alias Palee.Media

  require Logger

  def call(_context, _scope, []), do: :ok

  def call(context, scope, ids) do
    {:ok, deleted} = Media.delete(context, scope, ids)
    owner = MediaStorage.owner(context, scope)

    objects =
      for media <- deleted, key <- Media.object_keys(media) do
        %{bucket: Media.bucket(media.purpose), key: key}
      end

    case MediaStorage.delete(owner, objects) do
      {:ok, _count} ->
        :ok

      {:error, reason} ->
        # The rows are gone; a leftover object stays inside the owner's prefix
        # and is removed by the tenant purge or account deletion.
        Logger.warning("media object delete failed: #{inspect(reason)}")
        :ok
    end
  end
end
