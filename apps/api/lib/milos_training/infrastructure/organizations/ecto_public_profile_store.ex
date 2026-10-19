defmodule MilosTraining.Infrastructure.Organizations.EctoPublicProfileStore do
  @moduledoc "Ecto adapter of gym public profiles (ADR-142)."

  @behaviour MilosTraining.Organizations.Ports.PublicProfileStore

  alias MilosTraining.Organizations.{PublicProfile, TagSuggestion}
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

  @impl true
  def create_suggestion(%{organization_id: organization_id}, params) do
    %TagSuggestion{}
    |> TagSuggestion.changeset(Map.put(params, "organization_id", organization_id))
    |> Repo.insert()
    |> case do
      {:ok, suggestion} -> {:ok, Map.take(suggestion, [:id, :list, :name, :status, :inserted_at])}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def pending_suggestions do
    %{rows: rows} =
      Repo.query!(
        "SELECT id, organization_name, list, name, inserted_at FROM milos_pending_tag_suggestions()"
      )

    Enum.map(rows, fn [id, organization_name, list, name, inserted_at] ->
      %{
        id: Ecto.UUID.load!(id),
        organization_name: organization_name,
        list: list,
        name: name,
        inserted_at: DateTime.from_naive!(inserted_at, "Etc/UTC")
      }
    end)
  end

  @impl true
  def resolve_suggestion(id, status) do
    with {:ok, uuid} <- Ecto.UUID.dump(id),
         %{rows: [[1]]} <-
           Repo.query!("SELECT milos_resolve_tag_suggestion($1, $2)", [uuid, status]) do
      :ok
    else
      _missing -> {:error, :not_found}
    end
  end

  defp normalize(nil), do: nil

  defp normalize(%PublicProfile{} = profile) do
    Map.take(profile, [
      :organization_id,
      :about,
      :disciplines,
      :languages,
      :audiences,
      :amenities,
      :services,
      :cover_photo_id,
      :photo_ids,
      :published_snapshot,
      :published_at,
      :lock_version,
      :updated_at
    ])
  end
end
