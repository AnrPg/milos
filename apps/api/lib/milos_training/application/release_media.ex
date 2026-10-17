defmodule MilosTraining.Application.ReleaseMedia do
  @moduledoc """
  ADR-148: deletes media a consumer no longer references (rows and objects).
  Used when a box photo is removed from the profile, a post is deleted, or
  the orphan sweep finds an upload nobody attached.
  """

  alias MilosTraining.Application.MediaStorage
  alias MilosTraining.Media

  require Logger

  def call(_context, _scope, []), do: :ok

  def call(context, scope, ids) do
    {:ok, deleted} = Media.delete(context, scope, ids)
    owner = MediaStorage.owner(context, scope)
    objects = Enum.map(deleted, &%{bucket: Media.bucket(&1.purpose), key: &1.object_key})

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
