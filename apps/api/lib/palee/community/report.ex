defmodule Palee.Community.Report do
  @moduledoc """
  Something a member flagged in a club (ADR-143, board 7 Q4–Q5): a post, a
  comment, a whole group, or a person's Partners profile (ADR-169). It stays `open` until staff act on the item or
  decide nothing is needed; every open report on the same item closes
  together.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @target_types ~w(post comment channel partner)
  @reasons ~w(spam harassment inappropriate other)
  @statuses ~w(open actioned dismissed)
  @resolutions ~w(hidden deleted archived none)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_reports" do
    field :organization_id, :binary_id, read_after_writes: true
    field :club_id, :binary_id
    field :channel_id, :binary_id
    field :target_type, :string
    field :target_id, :binary_id
    field :target_author_id, :binary_id
    field :reporter_id, :binary_id
    field :reason, :string
    field :note, :string
    field :status, :string, default: "open"
    field :resolution, :string
    field :resolved_by_id, :binary_id
    field :resolved_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(report \\ %__MODULE__{}, attrs) do
    report
    |> cast(attrs, [
      :organization_id,
      :club_id,
      :channel_id,
      :target_type,
      :target_id,
      :target_author_id,
      :reporter_id,
      :reason,
      :note
    ])
    |> update_change(:note, &blank_to_nil/1)
    |> validate_required([:club_id, :target_type, :target_id, :reporter_id, :reason])
    |> validate_inclusion(:target_type, @target_types)
    |> validate_inclusion(:reason, @reasons)
    |> validate_length(:note, max: 500)
    |> unique_constraint([:target_type, :target_id, :reporter_id],
      name: :community_reports_target_type_target_id_reporter_id_index,
      message: "already_reported"
    )
  end

  def target_types, do: @target_types
  def reasons, do: @reasons
  def statuses, do: @statuses
  def resolutions, do: @resolutions

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value), do: value |> String.trim() |> then(&if(&1 == "", do: nil, else: &1))
end
