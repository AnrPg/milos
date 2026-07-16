defmodule MilosTraining.Application.SharePR do
  alias MilosTraining.Pantheon.PRStore
  alias MilosTraining.{Identity, Localization}

  def call(id, user_id) do
    case PRStore.get_pr_for_user(id, user_id) do
      nil ->
        {:error, :not_found}

      pr ->
        locale =
          case Identity.find_by_id(user_id) do
            %{preferred_locale: value} when is_binary(value) -> value
            _ -> "en"
          end

        {:ok, %{message: format_message(pr, locale)}}
    end
  end

  defp format_message(pr, locale) do
    score_str = format_score(pr.current_score, pr.unit)
    date_str = format_date(pr.beaten_on)
    unit = Localization.translate(locale, unit_message(pr.unit), %{}, "sharing")

    "🏆 " <>
      Localization.translate(
        locale,
        "New PR — %{name}: %{score} %{unit} (achieved on %{date})",
        %{name: pr.name, score: score_str, unit: unit, date: date_str},
        "sharing"
      )
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
      {:ok, date} -> Date.to_iso8601(date)
      _ -> date_str
    end
  end

  defp format_date(%Date{} = date), do: Date.to_iso8601(date)

  defp unit_message("mins_secs"), do: "minutes and seconds"
  defp unit_message("reps"), do: "repetitions"
  defp unit_message("sets"), do: "sets"
  defp unit_message("kcals"), do: "kilocalories"
  defp unit_message("m"), do: "metres"
  defp unit_message("kg"), do: "kilograms"
  defp unit_message(unit), do: to_string(unit)
end
