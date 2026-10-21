defmodule MilosTraining.Application.MediaConsumers do
  @moduledoc """
  Whatever an upload is attached to learns when the upload changes (it
  finished processing, was rejected or timed out): a post refreshes its
  media snapshot (ADR-157), a body snapshot its photo row (ADR-158).
  """

  alias MilosTraining.Application.{BodyPhotos, PostMedia}

  def refresh(context, %{attached_type: "body_snapshot"} = media) do
    BodyPhotos.refresh(context, media)
  end

  def refresh(_context, media) do
    _refreshed = media |> PostMedia.ref_of() |> PostMedia.refresh()
    :ok
  end
end
