defmodule MilosTraining.Infrastructure.Organizations.EctoPublicProfileStore do
  @moduledoc "Ecto adapter of gym public profiles (ADR-142)."

  @behaviour MilosTraining.Organizations.Ports.PublicProfileStore

  alias MilosTraining.Organizations.PublicProfile
  alias MilosTraining.Repo

  @impl true
  def get(%{organization_id: organization_id}) do
    PublicProfile |> Repo.get_by(organization_id: organization_id) |> normalize()
  end

  @impl true
  def upsert(%{organization_id: organization_id}, params) do
    profile =
      Repo.get_by(PublicProfile, organization_id: organization_id) ||
        %PublicProfile{organization_id: organization_id}

    profile
    |> PublicProfile.changeset(Map.put(params, "organization_id", organization_id))
    |> Repo.insert_or_update()
    |> case do
      {:ok, profile} -> {:ok, normalize(profile)}
      {:error, changeset} -> {:error, changeset}
    end
  rescue
    Ecto.StaleEntryError -> {:error, :stale_profile}
  end

  defp normalize(nil), do: nil

  defp normalize(%PublicProfile{} = profile) do
    Map.take(profile, [
      :organization_id,
      :about,
      :disciplines,
      :languages,
      :audiences,
      :photo_ids,
      :published_at,
      :lock_version,
      :updated_at
    ])
  end
end
