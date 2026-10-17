defmodule MilosTraining.Application.BoxPublicProfile do
  @moduledoc """
  ADR-142: a gym's public profile as staff edit it (Σχετικά of the public
  box page): the stored profile with its photos resolved to URLs. A gym
  without a stored profile reads as an empty, unpublished one.
  """

  alias MilosTraining.Application.MediaUrls
  alias MilosTraining.{Media, Organizations}

  def get(context) do
    with :ok <- Organizations.authorize_capability(context, :manage_settings) do
      {:ok, present(context, Organizations.get_public_profile(context))}
    end
  end

  @doc "A profile map with `photos` in place of `photo_ids`."
  def present(context, nil), do: present(context, empty(context))

  def present(context, profile) do
    photos =
      context
      |> Media.list(:tenant, profile.photo_ids)
      |> Map.new(&{&1.id, &1})
      |> then(fn by_id -> profile.photo_ids |> Enum.map(&by_id[&1]) |> Enum.reject(&is_nil/1) end)
      |> then(&MediaUrls.present_all(context, &1))

    profile
    |> Map.delete(:photo_ids)
    |> Map.merge(%{photos: photos, published: not is_nil(profile.published_at)})
  end

  defp empty(context) do
    %{
      organization_id: context.organization_id,
      about: nil,
      disciplines: [],
      languages: [],
      audiences: [],
      photo_ids: [],
      published_at: nil,
      lock_version: 0,
      updated_at: nil
    }
  end
end
