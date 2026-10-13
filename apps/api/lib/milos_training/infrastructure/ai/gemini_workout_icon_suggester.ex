defmodule MilosTraining.Infrastructure.Ai.GeminiWorkoutIconSuggester do
  @moduledoc """
  Asks Google Gemini for one fitting emoji per workout (see ADR-136).

  Optional: without `GEMINI_API_KEY` it returns `{:error, :not_configured}` and
  the library falls back to its keyword rules. Only the workout's title, type,
  description and section/movement names are sent — never athlete data.
  """

  @behaviour MilosTraining.Application.Ports.WorkoutIconSuggester

  @endpoint "https://generativelanguage.googleapis.com/v1beta/models"

  @instructions """
  You pick the icon for a workout file in a gym coach's library.
  Reply with exactly one emoji and nothing else.
  Choose what a coach would recognise at a glance, for example:
  💆 deload, recovery, massage, spa · 🧘 mobility, yoga, stretching · 🫀 cardio, engine, conditioning ·
  🏋️ barbell or strength work · 🤸 gymnastics and skills · 🏃 running · 🚣 rowing · 🚴 bike ·
  🏊 swimming · 🎖️ hero WODs · 🏆 benchmarks and tests · ⏱️ EMOM, AMRAP, intervals ·
  🤝 partner or team · 🔥 short, very intense metcons · 🦵 legs · 💪 upper body · 🧱 core.
  The workout may be written in Greek or any other language.
  """

  @impl true
  def suggest(summary) do
    config = Application.get_env(:milos_training, :gemini, [])

    case Keyword.get(config, :api_key) do
      key when is_binary(key) and key != "" ->
        request(key, Keyword.get(config, :icon_model), summary)

      _missing ->
        {:error, :not_configured}
    end
  end

  defp request(api_key, model, summary) do
    body = %{
      systemInstruction: %{parts: [%{text: @instructions}]},
      contents: [%{role: "user", parts: [%{text: describe(summary)}]}],
      generationConfig: %{
        temperature: 0.2,
        maxOutputTokens: 16,
        thinkingConfig: %{thinkingBudget: 0}
      }
    }

    "#{@endpoint}/#{model || "gemini-2.5-flash-lite"}:generateContent"
    |> Req.post(
      json: body,
      headers: [{"x-goog-api-key", api_key}],
      receive_timeout: 10_000,
      retry: false
    )
    |> case do
      {:ok, %Req.Response{status: 200, body: %{"candidates" => [candidate | _]}}} ->
        extract_text(candidate)

      {:ok, %Req.Response{status: status}} ->
        {:error, {:gemini_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_text(%{"content" => %{"parts" => [%{"text" => text} | _]}}), do: {:ok, text}
  defp extract_text(_candidate), do: {:error, :empty_suggestion}

  defp describe(summary) do
    [
      "Title: #{summary.title}",
      summary.type && "Type: #{summary.type}",
      present(summary.description) && "Description: #{String.slice(summary.description, 0, 400)}",
      summary.sections != [] && "Sections: #{Enum.join(summary.sections, ", ")}",
      summary.movements != [] && "Movements: #{Enum.join(summary.movements, ", ")}"
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join("\n")
  end

  defp present(value), do: is_binary(value) and String.trim(value) != ""
end
