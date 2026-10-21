defmodule Palee.Application.PublishBoxPublicProfile do
  @moduledoc """
  Board 3 Q8: «Δημοσίευση» copies the draft into the snapshot visitors see;
  it needs the about text and a discipline. Unpublishing hides the page at
  once and keeps the draft. The first publication time is kept.
  """

  alias Palee.Application.{BoxPublicProfile, UpdateBoxPublicProfile}
  alias Palee.Organizations

  def publish(context, params \\ %{}) do
    current = Organizations.get_public_profile(context)

    with :ok <- Organizations.authorize_capability(context, :manage_settings),
         :ok <- fresh(params, current),
         %{} <- current || {:error, :public_profile_empty},
         [] <- Organizations.box_profile_missing(current) do
      attrs = %{
        "published_snapshot" => BoxPublicProfile.snapshot(current),
        "published_at" => current.published_at || DateTime.utc_now()
      }

      with {:ok, profile} <- Organizations.upsert_public_profile(context, attrs) do
        :ok = UpdateBoxPublicProfile.settle_media(context, current, profile)
        {:ok, BoxPublicProfile.present(context, profile)}
      end
    else
      [_ | _] -> {:error, :public_profile_empty}
      error -> error
    end
  end

  def unpublish(context) do
    current = Organizations.get_public_profile(context)

    with :ok <- Organizations.authorize_capability(context, :manage_settings),
         {:ok, profile} <-
           Organizations.upsert_public_profile(context, %{
             "published_snapshot" => nil,
             "published_at" => nil
           }) do
      :ok = UpdateBoxPublicProfile.settle_media(context, current, profile)
      {:ok, BoxPublicProfile.present(context, profile)}
    end
  end

  defp fresh(%{"lock_version" => version}, %{lock_version: current}) when version != current,
    do: {:error, :stale_profile}

  defp fresh(_params, _current), do: :ok
end
