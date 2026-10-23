defmodule Palee.Perks.Rules do
  @moduledoc """
  The combinable rules of a perk version (ADR-191 §4), one validated
  document with its own `schema_version`, so a new kind of rule is a new
  field here, not a new table:

    * `valid_from` / `valid_until` — the window (business dates);
    * `recurring` — optional weekly windows («Δευτέρα–Παρασκευή 06:00–10:00»),
      in the business's local time; outside them the perk can't be claimed
      or used;
    * `limits` — overall, per member, and per period (day / week / month)
      for everyone and for each member;
    * `eligibility` — packages (memberships are packages), member groups
      (club groups), minimum tenure in days; branches are the perk's
      covering scope (ADR-186 §8);
    * `channel` — `in_store`, `online` or `both`;
    * `stacking` — free notes on combining with other offers.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__.{Eligibility, Limits, Window}

  @schema_version 1
  @channels ~w(in_store online both)

  @primary_key false
  embedded_schema do
    field :schema_version, :integer, default: @schema_version
    field :valid_from, :date
    field :valid_until, :date
    field :channel, :string, default: "both"
    field :stacking, :string
    embeds_many :recurring, Window, on_replace: :delete
    embeds_one :limits, Limits, on_replace: :update, defaults_to_struct: true
    embeds_one :eligibility, Eligibility, on_replace: :update, defaults_to_struct: true
  end

  @type t :: %__MODULE__{}

  def schema_version, do: @schema_version
  def channels, do: @channels

  def changeset(rules \\ %__MODULE__{}, attrs) do
    rules
    |> cast(attrs, [:valid_from, :valid_until, :channel, :stacking])
    |> put_change(:schema_version, @schema_version)
    |> validate_inclusion(:channel, @channels)
    |> validate_length(:stacking, max: 1_000)
    |> cast_embed(:recurring)
    |> cast_embed(:limits)
    |> cast_embed(:eligibility)
    |> validate_length(:recurring, max: 14)
    |> validate_window()
  end

  defp validate_window(changeset) do
    from = get_field(changeset, :valid_from)
    until = get_field(changeset, :valid_until)

    if from && until && Date.compare(until, from) == :lt,
      do: add_error(changeset, :valid_until, "must be on or after the start date"),
      else: changeset
  end
end
