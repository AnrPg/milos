defmodule MilosTraining.Infrastructure.Feedback.EctoFeedbackStore do
  @behaviour MilosTraining.Feedback.Ports.FeedbackStore

  import Ecto.Query

  alias Ecto.Multi
  alias MilosTraining.Feedback.{Review, ReviewAnswer}
  alias MilosTraining.Repo

  @impl true
  def submit_review(user_id, params) do
    params =
      params
      |> string_key_map()
      |> Map.put("user_id", user_id)

    answers = normalize_answers(Map.get(params, "answers", []))

    Multi.new()
    |> Multi.insert(:review, Review.changeset(%Review{}, Map.delete(params, "answers")))
    |> Multi.run(:answers, fn repo, %{review: review} ->
      answers
      |> Enum.map(fn answer ->
        answer
        |> Map.put("review_id", review.id)
        |> then(&ReviewAnswer.changeset(%ReviewAnswer{}, &1))
      end)
      |> insert_answers(repo)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{review: review, answers: answers}} ->
        {:ok, normalize_review(review, answers)}

      {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  @impl true
  def list_reviews_for_user(user_id) do
    Review
    |> where([review], review.user_id == ^user_id)
    |> order_by([review], desc: review.inserted_at)
    |> Repo.all()
    |> preload_answers()
  end

  @impl true
  def list_reviews(filters) do
    filters = string_key_map(filters || %{})

    Review
    |> maybe_filter(:target_type, filters["target_type"])
    |> maybe_filter(:status, filters["status"])
    |> maybe_filter(:sentiment, filters["sentiment"])
    |> order_by([review], desc: review.inserted_at)
    |> offset(^parse_offset(filters["offset"]))
    |> limit(^parse_limit(filters["limit"]))
    |> Repo.all()
    |> preload_answers()
  end

  @impl true
  def update_review_status(review_id, params) do
    attrs = moderation_attrs(params)

    case Repo.get(Review, review_id) do
      nil ->
        {:error, :not_found}

      %Review{} = review ->
        review
        |> Review.changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, updated_review} ->
            {:ok, normalize_review(updated_review, list_answers(updated_review.id))}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:error, changeset}
        end
    end
  end

  @impl true
  def review_summary(filters) do
    filters = string_key_map(filters || %{})
    since = summary_since(filters["days"])

    %{
      since: since,
      total: count_reviews(since),
      average_rating: average_rating(since),
      by_status: count_reviews_by(:status, since),
      by_sentiment: count_reviews_by(:sentiment, since),
      by_target_type: count_reviews_by(:target_type, since),
      low_rating_count: low_rating_count(since)
    }
  end

  defp insert_answers([], _repo), do: {:ok, []}

  defp insert_answers(changesets, repo) do
    Enum.reduce_while(changesets, {:ok, []}, fn changeset, {:ok, answers} ->
      case repo.insert(changeset) do
        {:ok, answer} -> {:cont, {:ok, [answer | answers]}}
        {:error, %Ecto.Changeset{} = changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, answers} -> {:ok, Enum.reverse(answers)}
      error -> error
    end
  end

  defp preload_answers(reviews) do
    answers_by_review_id =
      reviews
      |> Enum.map(& &1.id)
      |> case do
        [] ->
          %{}

        review_ids ->
          ReviewAnswer
          |> where([answer], answer.review_id in ^review_ids)
          |> order_by([answer], asc: answer.inserted_at)
          |> Repo.all()
          |> Enum.group_by(& &1.review_id)
      end

    Enum.map(reviews, fn review ->
      normalize_review(review, Map.get(answers_by_review_id, review.id, []))
    end)
  end

  defp list_answers(review_id) do
    ReviewAnswer
    |> where([answer], answer.review_id == ^review_id)
    |> order_by([answer], asc: answer.inserted_at)
    |> Repo.all()
  end

  defp maybe_filter(query, _field, value) when value in [nil, "", "all"], do: query

  defp maybe_filter(query, field, value) do
    where(query, [record], field(record, ^field) == ^value)
  end

  defp moderation_attrs(status) when is_binary(status), do: %{status: status}

  defp moderation_attrs(params) when is_map(params) do
    params
    |> string_key_map()
    |> Map.take(["status", "tags"])
    |> normalize_moderation_tags()
  end

  defp moderation_attrs(_params), do: %{}

  defp normalize_moderation_tags(%{"tags" => tags} = params) when is_binary(tags) do
    Map.put(params, "tags", split_tags(tags))
  end

  defp normalize_moderation_tags(%{"tags" => tags} = params) when is_list(tags) do
    Map.put(params, "tags", Enum.filter(tags, &is_binary/1))
  end

  defp normalize_moderation_tags(params), do: params

  defp split_tags(tags) do
    tags
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_review(%Review{} = review, answers) do
    %{
      id: review.id,
      user_id: review.user_id,
      target_type: review.target_type,
      target_id: review.target_id,
      target_snapshot: review.target_snapshot || %{},
      questionnaire_id: review.questionnaire_id,
      rating: review.rating,
      sentiment: review.sentiment,
      visibility: review.visibility,
      body: review.body,
      status: review.status,
      tags: review.tags || [],
      params: review.params || %{},
      answers: Enum.map(answers, &normalize_answer/1),
      inserted_at: review.inserted_at,
      updated_at: review.updated_at
    }
  end

  defp normalize_answer(%ReviewAnswer{} = answer) do
    %{
      id: answer.id,
      review_id: answer.review_id,
      question_key: answer.question_key,
      question_text: answer.question_text,
      answer_text: answer.answer_text,
      rating_value: answer.rating_value,
      inserted_at: answer.inserted_at,
      updated_at: answer.updated_at
    }
  end

  defp normalize_answers(answers) when is_list(answers) do
    Enum.map(answers, fn answer -> string_key_map(answer || %{}) end)
  end

  defp normalize_answers(_), do: []

  defp count_reviews(since) do
    Review
    |> where([review], review.inserted_at >= ^since)
    |> Repo.aggregate(:count)
  end

  defp average_rating(since) do
    Review
    |> where([review], review.inserted_at >= ^since)
    |> where([review], not is_nil(review.rating))
    |> Repo.aggregate(:avg, :rating)
    |> case do
      nil -> nil
      value -> Decimal.to_float(value)
    end
  end

  defp count_reviews_by(field, since) do
    Review
    |> where([review], review.inserted_at >= ^since)
    |> group_by([review], field(review, ^field))
    |> select([review], {field(review, ^field), count(review.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp low_rating_count(since) do
    Review
    |> where([review], review.inserted_at >= ^since)
    |> where([review], not is_nil(review.rating) and review.rating <= 2)
    |> Repo.aggregate(:count)
  end

  defp summary_since(nil), do: DateTime.add(DateTime.utc_now(), -30 * 86_400, :second)

  defp summary_since(days) when is_integer(days) do
    DateTime.add(DateTime.utc_now(), -max(days, 1) * 86_400, :second)
  end

  defp summary_since(days) when is_binary(days) do
    case Integer.parse(days) do
      {value, ""} -> summary_since(value)
      _ -> summary_since(nil)
    end
  end

  defp parse_limit(nil), do: 100
  defp parse_limit(limit) when is_integer(limit), do: limit |> min(250) |> max(1)

  defp parse_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {value, ""} -> parse_limit(value)
      _ -> 100
    end
  end

  defp parse_offset(nil), do: 0
  defp parse_offset(offset) when is_integer(offset), do: max(offset, 0)

  defp parse_offset(offset) when is_binary(offset) do
    case Integer.parse(offset) do
      {value, ""} -> parse_offset(value)
      _ -> 0
    end
  end

  defp string_key_map(params) when is_map(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end
end
