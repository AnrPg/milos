defmodule MilosTraining.Community.Domain.PostMediaPolicy do
  @moduledoc """
  Photos and videos in posts (ADR-157). Pure.

  - A post carries up to ten photos, or one video, never both.
  - A post may be published while its media are still processing. Until all
    of them are ready only its author sees it, marked «επεξεργάζεται»; a post
    with a media item that could not be processed is `failed` and stays with
    its author. Once processed, every photo shows: there is no automatic
    check, safety rests on reports (ADR-143).
  """

  @max_images 10
  @statuses ~w(ready processing failed)

  def max_images, do: @max_images
  def statuses, do: @statuses

  @doc "Whether media of these kinds (`image`, `video`), in order, may form one post."
  def compose([]), do: :ok

  def compose(kinds) when is_list(kinds) do
    images = Enum.count(kinds, &(&1 == "image"))
    videos = Enum.count(kinds, &(&1 == "video"))

    cond do
      images + videos != length(kinds) -> {:error, :invalid_media}
      videos > 0 and images > 0 -> {:error, :mixed_media}
      videos > 1 -> {:error, :too_many_media}
      images > @max_images -> {:error, :too_many_media}
      true -> :ok
    end
  end

  @doc """
  A post's media status from the status of each of its media (`pending`,
  `processing`, `ready`, `rejected`, or `missing` when it is gone).
  """
  def status([]), do: "ready"

  def status(states) when is_list(states) do
    cond do
      Enum.any?(states, &(&1 in ["rejected", "missing"])) -> "failed"
      Enum.any?(states, &(&1 != "ready")) -> "processing"
      true -> "ready"
    end
  end

  @doc "Who sees a post with media: everyone once it is ready, its author always."
  def visible?(%{media_status: "ready"}, _viewer_id), do: true
  def visible?(%{media_status: nil}, _viewer_id), do: true

  def visible?(%{author_id: author_id}, viewer_id) when is_binary(viewer_id),
    do: author_id == viewer_id

  def visible?(_post, _viewer_id), do: false
end
