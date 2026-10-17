defmodule MilosTraining.Application.UpdateBoxPublicProfile do
  @moduledoc """
  ADR-142: staff edit the gym's public profile. Photos are ready
  `box_photo` media of this gym (ADR-148); photos dropped from the profile
  are released (row and object deleted). Publishing needs something to show
  (an about text or a discipline); unpublishing hides the public page at
  once.
  """

  alias MilosTraining.Application.{BoxPublicProfile, ReleaseMedia}
  alias MilosTraining.{Media, Organizations}

  @fields ~w(about disciplines languages audiences)

  def call(context, params) when is_map(params) do
    params = Map.new(params, fn {key, value} -> {to_string(key), value} end)
    current = Organizations.get_public_profile(context)

    with :ok <- Organizations.authorize_capability(context, :manage_settings),
         :ok <- fresh(params, current),
         {:ok, photo_ids} <- photo_ids(params, current),
         {:ok, _photos} <- Media.fetch_ready(context, "box_photo", photo_ids),
         attrs = attrs(params, photo_ids),
         {:ok, attrs} <- publication(attrs, params, current),
         {:ok, profile} <- Organizations.upsert_public_profile(context, attrs) do
      now = DateTime.utc_now()
      previous_ids = if current, do: current.photo_ids, else: []
      :ok = Media.set_attached(context, :tenant, photo_ids, now)
      :ok = ReleaseMedia.call(context, :tenant, previous_ids -- photo_ids)
      {:ok, BoxPublicProfile.present(context, profile)}
    end
  end

  def call(_context, _params), do: {:error, :invalid_public_profile}

  # The editor sends the version it read; a concurrent edit wins once.
  defp fresh(%{"lock_version" => version}, %{lock_version: current}) when version != current,
    do: {:error, :stale_profile}

  defp fresh(_params, _current), do: :ok

  defp photo_ids(%{"photo_ids" => ids}, _current), do: Organizations.normalize_box_photo_ids(ids)
  defp photo_ids(_params, nil), do: {:ok, []}
  defp photo_ids(_params, current), do: {:ok, current.photo_ids}

  defp attrs(params, photo_ids) do
    params
    |> Map.take(@fields)
    |> Map.put("photo_ids", photo_ids)
  end

  # `published` true keeps the first publication time; false clears it.
  defp publication(attrs, %{"published" => false}, _current),
    do: {:ok, Map.put(attrs, "published_at", nil)}

  defp publication(attrs, %{"published" => true}, current) do
    merged = %{
      about: Map.get(attrs, "about", current && current.about),
      disciplines: Map.get(attrs, "disciplines", (current && current.disciplines) || [])
    }

    cond do
      not Organizations.box_profile_publishable?(merged) ->
        {:error, :public_profile_empty}

      current && current.published_at ->
        {:ok, attrs}

      true ->
        {:ok, Map.put(attrs, "published_at", DateTime.utc_now())}
    end
  end

  defp publication(attrs, _params, _current), do: {:ok, attrs}
end
