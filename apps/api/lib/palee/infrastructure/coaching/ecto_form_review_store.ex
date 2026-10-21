defmodule Palee.Infrastructure.Coaching.EctoFormReviewStore do
  @moduledoc "Ecto adapter for form reviews and overdue-reply alerts (ADR-098)."

  @behaviour Palee.Coaching.Ports.FormReviewStore

  import Ecto.Query

  alias Palee.Coaching.{FormReview, ReplyAlert}
  alias Palee.Repo

  @impl true
  def create_review(%{organization_id: organization_id}, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> FormReview.submit_changeset()
    |> Repo.insert()
    |> result()
  end

  @impl true
  def get_review(%{organization_id: organization_id}, id) do
    case fetch(organization_id, id) do
      nil -> nil
      review -> normalize(review)
    end
  end

  @impl true
  def list_reviews(%{organization_id: organization_id}, filters) do
    FormReview
    |> where([review], review.organization_id == ^organization_id)
    |> maybe_filter(:user_id, filters[:user_id])
    |> maybe_filter(:status, filters[:status])
    |> order_by([review], desc: review.inserted_at)
    |> limit(200)
    |> join(:left, [review], user in "users", on: user.id == review.user_id)
    |> select([review, user], {review, user.nickname})
    |> Repo.all()
    |> Enum.map(fn {review, nickname} ->
      review |> normalize() |> Map.put(:nickname, nickname)
    end)
  end

  @impl true
  def review(%{organization_id: organization_id}, id, attrs) do
    case fetch_for_update(organization_id, id) do
      nil -> {:error, :not_found}
      review -> review |> FormReview.review_changeset(attrs) |> Repo.update() |> result()
    end
  end

  @impl true
  def withdraw(%{organization_id: organization_id}, id) do
    case fetch_for_update(organization_id, id) do
      nil -> {:error, :not_found}
      review -> review |> FormReview.withdraw_changeset() |> Repo.update() |> result()
    end
  end

  @impl true
  def alerted_message_ids(%{organization_id: organization_id}, message_ids) do
    ReplyAlert
    |> where(
      [alert],
      alert.organization_id == ^organization_id and alert.message_id in ^message_ids
    )
    |> select([alert], alert.message_id)
    |> Repo.all()
  end

  @impl true
  def record_alert(%{organization_id: organization_id}, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> ReplyAlert.changeset()
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:organization_id, :message_id])
    |> case do
      {:ok, _alert} -> :ok
      error -> error
    end
  end

  defp maybe_filter(query, _field, nil), do: query

  defp maybe_filter(query, field, value),
    do: where(query, [review], field(review, ^field) == ^value)

  defp fetch(organization_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get_by(FormReview, id: id, organization_id: organization_id)
      :error -> nil
    end
  end

  defp fetch_for_update(organization_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        FormReview
        |> where([review], review.id == ^id and review.organization_id == ^organization_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      :error ->
        nil
    end
  end

  defp result({:ok, review}), do: {:ok, normalize(review)}
  defp result({:error, changeset}), do: {:error, changeset}

  defp normalize(%FormReview{} = review) do
    Map.take(review, [
      :id,
      :user_id,
      :video_url,
      :note,
      :exercise_name,
      :execution_id,
      :status,
      :reservation_id,
      :reviewer_id,
      :feedback,
      :reviewed_at,
      :inserted_at
    ])
  end
end
