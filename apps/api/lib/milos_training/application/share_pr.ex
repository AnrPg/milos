defmodule MilosTraining.Application.SharePR do
  alias MilosTraining.Pantheon.PRStore

  def call(id, user_id) do
    case PRStore.get_pr_for_user(id, user_id) do
      nil ->
        {:error, :not_found}

      pr ->
        {:ok, %{message: format_message(pr)}}
    end
  end

  defp format_message(pr) do
    score_str = format_score(pr.current_score, pr.unit)
    date_str = format_date(pr.beaten_on)
    "🏆 New PR — #{pr.name}: #{score_str} #{pr.unit} (beaten on #{date_str})"
  end

  defp format_score(score, "mins_secs") do
    total_secs = round(score)
    m = div(total_secs, 60) |> Integer.to_string() |> String.pad_leading(2, "0")
    s = rem(total_secs, 60) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{m}:#{s}"
  end

  defp format_score(score, _unit) do
    if score == trunc(score), do: Integer.to_string(trunc(score)), else: Float.to_string(score)
  end

  defp format_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> Calendar.strftime(date, "%b %d, %Y")
      _ -> date_str
    end
  end

  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%b %d, %Y")
end
