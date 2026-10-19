defmodule MilosTraining.Application.UpdateBoxPublicProfile do
  @moduledoc """
  ADR-142, board 3: staff edit the draft of the gym's public profile.
  Visitors keep seeing the last published snapshot until «Δημοσίευση»
  (`PublishBoxPublicProfile`). Photos are ready `box_photo` media of this
  gym (ADR-148); a photo is released once neither the draft nor the
  published snapshot uses it.
  """

  alias MilosTraining.Application.{BoxPublicProfile, ReleaseMedia}
  alias MilosTraining.{Media, Organizations}

  @fields ~w(about disciplines languages audiences amenities services)

  def call(context, params) when is_map(params) do
    params = Map.new(params, fn {key, value} -> {to_string(key), value} end)
    current = Organizations.get_public_profile(context)

    with :ok <- Organizations.authorize_capability(context, :manage_settings),
         :ok <- fresh(params, current),
         {:ok, photo_ids} <- photo_ids(params, current),
         {:ok, cover_id} <- cover_id(params, current),
         {:ok, _photos} <-
           Media.fetch_ready(context, "box_photo", Enum.reject([cover_id | photo_ids], &is_nil/1)),
         attrs =
           params
           |> Map.take(@fields)
           |> default_languages(current)
           |> Map.merge(%{"photo_ids" => photo_ids, "cover_photo_id" => cover_id}),
         {:ok, profile} <- Organizations.upsert_public_profile(context, attrs) do
      :ok = settle_media(context, current, profile)
      {:ok, BoxPublicProfile.present(context, profile)}
    end
  end

  def call(_context, _params), do: {:error, :invalid_public_profile}

  # The first save stores the languages the editor showed pre-picked.
  defp default_languages(attrs, nil),
    do: Map.put_new(attrs, "languages", Organizations.default_box_languages())

  defp default_languages(attrs, _current), do: attrs

  @doc """
  Marks what the profile uses as attached and releases what `before` used
  and `now` no longer does, counting both the draft and the snapshot.
  """
  def settle_media(context, before, now) do
    kept = BoxPublicProfile.media_ids(now)
    :ok = Media.set_attached(context, :tenant, kept, DateTime.utc_now())
    ReleaseMedia.call(context, :tenant, BoxPublicProfile.media_ids(before) -- kept)
  end

  # The editor sends the version it read; a concurrent edit wins once.
  defp fresh(%{"lock_version" => version}, %{lock_version: current}) when version != current,
    do: {:error, :stale_profile}

  defp fresh(_params, _current), do: :ok

  defp photo_ids(%{"photo_ids" => ids}, _current), do: Organizations.normalize_box_photo_ids(ids)
  defp photo_ids(_params, nil), do: {:ok, []}
  defp photo_ids(_params, current), do: {:ok, current.photo_ids}

  defp cover_id(%{"cover_photo_id" => nil}, _current), do: {:ok, nil}

  defp cover_id(%{"cover_photo_id" => id}, _current) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :invalid_media}
    end
  end

  defp cover_id(_params, nil), do: {:ok, nil}
  defp cover_id(_params, current), do: {:ok, current.cover_photo_id}
end
