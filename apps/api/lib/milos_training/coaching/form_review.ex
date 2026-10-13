defmodule MilosTraining.Coaching.FormReview do
  @moduledoc "A client's request for technique feedback on a video (ADR-098)."

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Coaching.Domain.FormReviewPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "coaching_form_reviews" do
    field :organization_id, :binary_id
    field :user_id, :binary_id
    field :video_url, :string
    field :note, :string
    field :exercise_name, :string
    field :execution_id, :binary_id
    field :status, :string, default: "submitted"
    field :reservation_id, :binary_id
    field :reviewer_id, :binary_id
    field :feedback, :string
    field :reviewed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def submit_changeset(params) do
    %__MODULE__{}
    |> cast(params, [
      :id,
      :organization_id,
      :user_id,
      :video_url,
      :note,
      :exercise_name,
      :execution_id,
      :reservation_id
    ])
    |> validate_required([:organization_id, :user_id, :video_url])
    |> validate_length(:note, max: 2000)
    |> validate_length(:exercise_name, max: 120)
    |> validate_change(:video_url, fn :video_url, url ->
      if FormReviewPolicy.valid_link?(url), do: [], else: [video_url: "must be an https link"]
    end)
  end

  def review_changeset(review, params) do
    review
    |> cast(params, [:reviewer_id, :feedback, :reviewed_at])
    |> put_change(:status, "reviewed")
    |> validate_required([:reviewer_id, :feedback, :reviewed_at])
    |> validate_length(:feedback, min: 2, max: 5000)
  end

  def withdraw_changeset(review), do: change(review, status: "withdrawn")
end
