defmodule Palee.Partners.SuggestionFeedback do
  @moduledoc """
  A person's «Δεν ταιριάζει» on one «Κλείστε μαζί» suggestion of one match
  (ADR-280 §4): the suggestion's key (`kind:id`) and why. One per person,
  match and key; answering again changes the reason. Only counts are shown.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Partners.Domain.SuggestionPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "partner_suggestion_feedback" do
    field :match_id, :binary_id
    field :user_id, :binary_id
    field :suggestion_key, :string
    field :reason, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:match_id, :user_id, :suggestion_key, :reason])
    |> validate_required([:match_id, :user_id, :suggestion_key, :reason])
    |> validate_length(:suggestion_key, min: 3, max: 120)
    |> validate_inclusion(:reason, SuggestionPolicy.feedback_reasons())
    |> foreign_key_constraint(:match_id)
  end
end
