defmodule Palee.Perks.PerkVersion do
  @moduledoc """
  One version of a perk (ADR-191 §6): the benefit, the rules, the method's
  settings and the terms members agree to when they claim. A change after
  the first claim makes a new version; claims keep theirs, so what a member
  agreed to is never rewritten.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Perks.{Benefit, Redemption, Rules}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "perk_versions" do
    field :organization_id, :binary_id, read_after_writes: true
    field :perk_id, :binary_id
    field :version, :integer
    embeds_one :benefit, Benefit, on_replace: :update
    embeds_one :rules, Rules, on_replace: :update
    embeds_one :redemption, Redemption, on_replace: :update
    field :terms, :string
    field :created_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @doc """
  The version document from `attrs` (`benefit`, `rules`, `redemption`,
  `terms`), on top of `base` (the previous version's values, or empty), for
  a perk whose method is `method`.
  """
  def changeset(base \\ %__MODULE__{}, attrs, method) do
    base
    |> cast(attrs, [:terms, :created_by_id])
    |> validate_length(:terms, max: 4_000)
    |> cast_embed(:benefit, required: true)
    |> cast_embed(:rules, required: true)
    |> cast_embed(:redemption, required: true, with: &Redemption.changeset(&1, &2, method))
  end

  @doc "A fresh, unsaved copy of a version's documents to build the next one on."
  def next_base(%__MODULE__{} = version),
    do: %__MODULE__{
      benefit: version.benefit,
      rules: version.rules,
      redemption: version.redemption,
      terms: version.terms
    }
end
