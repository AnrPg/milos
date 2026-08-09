defmodule MilosTraining.Feedback.Review do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "reviews" do
    field :organization_id, :binary_id
    field :user_id, :binary_id
    field :target_type, :string
    field :target_id, :binary_id
    field :review_identity_key, :string
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
      :organization_id,
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
    |> put_review_identity_key()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:questionnaire_id)
    |> unique_constraint(:target_id, name: :reviews_one_per_user_target_index)
  end

  defp put_review_identity_key(changeset) do
    user_id = get_field(changeset, :user_id)
    target_type = get_field(changeset, :target_type)
    target_id = get_field(changeset, :target_id)

    if user_id && target_type && target_id do
      put_change(changeset, :review_identity_key, "#{user_id}:#{target_type}:#{target_id}")
    else
      changeset
    end
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
