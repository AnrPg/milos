defmodule MilosTraining.Organizations.PublicProfile do
  @moduledoc "A gym's public profile, the «Σχετικά» of its public page (ADR-142)."

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Organizations.Domain.BoxProfilePolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organization_public_profiles" do
    field :organization_id, :binary_id
    field :about, :string
    field :disciplines, {:array, :string}, default: []
    field :languages, {:array, :string}, default: []
    field :audiences, {:array, :string}, default: []
    field :photo_ids, {:array, :binary_id}, default: []
    field :published_at, :utc_datetime_usec
    field :lock_version, :integer, default: 1

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(profile, params) do
    profile
    |> cast(params, [
      :organization_id,
      :about,
      :disciplines,
      :languages,
      :audiences,
      :photo_ids,
      :published_at
    ])
    |> validate_required([:organization_id])
    |> update_change(:about, &blank_to_nil/1)
    |> validate_length(:about, max: BoxProfilePolicy.max_about())
    |> update_change(:disciplines, &Enum.uniq/1)
    |> validate_subset(:disciplines, BoxProfilePolicy.disciplines())
    |> update_change(:audiences, &Enum.uniq/1)
    |> validate_subset(:audiences, BoxProfilePolicy.audiences())
    |> validate_languages()
    |> validate_length(:photo_ids, max: BoxProfilePolicy.max_photos())
    |> optimistic_lock(:lock_version)
    |> unique_constraint(:organization_id)
  end

  defp validate_languages(changeset) do
    case fetch_change(changeset, :languages) do
      {:ok, languages} ->
        case BoxProfilePolicy.normalize_languages(languages || []) do
          {:ok, languages} -> put_change(changeset, :languages, languages)
          {:error, _reason} -> add_error(changeset, :languages, "must be ISO 639-1 codes")
        end

      :error ->
        changeset
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(text) do
    case String.trim(text) do
      "" -> nil
      text -> text
    end
  end
end
