defmodule Palee.ScaleLevel do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # Tenant-owned since ADR-128: each organization has its own set, unique per
  # organization by slug and (active) sort order, under forced RLS.
  schema "scale_levels" do
    field :organization_id, :binary_id
    field :slug, :string
    field :label, :string
    field :sort_order, :integer
    field :is_active, :boolean, default: true

    timestamps()
  end

  def changeset(scale_level \\ %__MODULE__{}, params) do
    scale_level
    |> cast(params, [:organization_id, :slug, :label, :sort_order, :is_active])
    |> update_change(:slug, &normalize_slug/1)
    |> update_change(:label, &normalize_label/1)
    |> validate_required([:organization_id, :slug, :label, :sort_order])
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> validate_number(:sort_order, greater_than_or_equal_to: 1)
    |> foreign_key_constraint(:organization_id)
    |> unique_constraint(:slug, name: :scale_levels_organization_id_slug_index)
    |> unique_constraint(:sort_order, name: :scale_levels_organization_id_sort_order_index)
  end

  defp normalize_slug(nil), do: nil
  defp normalize_slug(slug), do: slug |> String.trim() |> String.downcase()

  defp normalize_label(nil), do: nil
  defp normalize_label(label), do: String.trim(label)
end
