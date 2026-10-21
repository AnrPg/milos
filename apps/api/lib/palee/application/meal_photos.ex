defmodule Palee.Application.MealPhotos do
  @moduledoc """
  The optional photo of a meal (ADR-159 §9): uploaded through the ADR-157
  pipeline into the member's private storage (server-stripped renditions),
  attached to its entry, shown with short-lived signed URLs, never posted
  without a separate confirmation, and deleted with its entry.
  """

  alias Palee.Application.{
    CompleteMediaUpload,
    MediaStorage,
    ReleaseMedia,
    RequestMediaUpload,
    WellnessConsent
  }

  alias Palee.Media

  @purpose "meal_photo"
  @renditions ~w(thumb feed full)

  def purpose, do: @purpose

  def capabilities,
    do: %{
      content_types: Media.content_types(@purpose) |> Enum.sort(),
      max_bytes: Media.max_bytes(@purpose)
    }

  @doc "Reserves an upload (needs the health-data consent)."
  def request_upload(context, params, now \\ DateTime.utc_now()) do
    with :ok <- WellnessConsent.require(context) do
      RequestMediaUpload.reserve(context, @purpose, params, now)
    end
  end

  @doc "The member's own unattached meal upload `id`, or `nil` for no photo."
  def prepare(_context, nil), do: {:ok, nil}

  def prepare(context, id) do
    case Media.list(context, :account, [id]) do
      [%{purpose: @purpose, attached_at: nil, status: status} = media]
      when status != "rejected" ->
        {:ok, media}

      _other ->
        {:error, :invalid_media}
    end
  end

  @doc "Attaches a prepared upload to its entry; finishing it starts processing."
  def attach(_context, _entry, nil, _now), do: :ok

  def attach(context, entry, media, now) do
    with :ok <- complete(context, media),
         {:ok, 1} <-
           Media.attach(
             context,
             :account,
             [media.id],
             %{type: "wellness_entry", id: entry.id},
             now
           ) do
      :ok
    else
      {:ok, 0} -> {:error, :invalid_media}
      {:error, reason} -> {:error, reason}
    end
  end

  defp complete(context, %{status: "pending", id: id}) do
    case CompleteMediaUpload.call(context, @purpose, id) do
      {:ok, _media} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp complete(_context, _media), do: :ok

  def release(_context, nil), do: :ok
  def release(context, id), do: ReleaseMedia.call(context, :account, [id])

  @doc "Every meal photo of the member (delete-all)."
  def release_all(context),
    do:
      ReleaseMedia.call(context, :account, Media.list_ids_by_purpose(context, :account, @purpose))

  @doc "`%{media_id => photo}` with signed URLs once the renditions exist."
  def present(_context, []), do: %{}

  def present(%{user_id: user_id} = context, ids) do
    owner = {:account, user_id}

    context
    |> Media.list(:account, Enum.uniq(ids))
    |> Map.new(fn media ->
      variants = if media.status == "ready", do: media.variants || %{}, else: %{}

      {media.id,
       %{
         id: media.id,
         status: media.status,
         width: media.width,
         height: media.height,
         placeholder: media.placeholder
       }
       |> Map.merge(
         Map.new(@renditions, &{String.to_atom(&1 <> "_url"), url(owner, variants, &1)})
       )}
    end)
  end

  defp url(owner, variants, name) do
    with %{"key" => key} <- Map.get(variants, name),
         {:ok, url} <- MediaStorage.read_url(owner, :media_private, key) do
      url
    else
      _missing -> nil
    end
  end
end
