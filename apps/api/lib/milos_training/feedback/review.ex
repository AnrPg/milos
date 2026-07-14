defmodule MilosTraining.Feedback.Review do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "reviews" do
    field :user_id, :binary_id
    field :target_type, :string
    field :target_id, :binary_id
    field :target_snapshot, :map, default: %{}
    field :questionnaire_id, :binary_id
    field :rating, :integer
    field :sentiment, :string, default: "neutral"
    field :visibility, :string, default: "user_visible"
    field :body, :string
    field :status, :string, default: "open"
    field :tags, {:array, :string}, default: []
    field :params, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(review \\ %__MODULE__{}, params) do
    review
    |> cast(normalize_params(params), [
      :user_id,
      :target_type,
      :target_id,
      :target_snapshot,
      :questionnaire_id,
      :rating,
      :sentiment,
      :visibility,
      :body,
      :status,
      :tags,
      :params
    ])
    |> validate_required([:user_id, :target_type, :sentiment, :visibility, :status])
    |> validate_inclusion(:target_type, [
      "workout",
      "execution",
      "exercise",
      "class_slot",
      "gym_parameter",
      "coaching_parameter",
      "membership_package",
      "app",
      "general"
    ])
    |> validate_number(:rating, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> validate_inclusion(:sentiment, ["positive", "neutral", "negative", "mixed"])
    |> validate_inclusion(:visibility, ["admin_only", "user_visible"])
    |> validate_inclusion(:status, ["open", "reviewed", "archived", "needs_follow_up"])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:questionnaire_id)
  end

  defp normalize_params(params) when is_map(params) do
    Map.new(params, fn
      {key, "private_coaching"} when key in [:target_type, "target_type"] ->
        {key, "coaching_parameter"}

      pair ->
        pair
    end)
  end
end
