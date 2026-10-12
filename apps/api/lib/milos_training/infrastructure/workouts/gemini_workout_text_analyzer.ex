defmodule MilosTraining.Infrastructure.Workouts.GeminiWorkoutTextAnalyzer do
  @moduledoc """
  `WorkoutTextAnalyzer` adapter backed by the Google Gemini `generateContent`
  API. Runs two agents:

    * `parse/2` – reads free text into the canonical schema; may be called
      again with `:repair` feedback (contract violations) by the caller;
    * `proofread/2` – proposes verbatim in-line text corrections.

  Both agents may call server-side tools (Gemini function calling), executed
  by `MilosTraining.Workouts.Domain.WorkoutAssistant.Tools`: exercise catalog
  lookup, timer format specs, unit conversion and, for the parser, a
  `validate_draft` self-check against the strict contract.

  Configuration (runtime):

      config :milos_training, :gemini,
        api_key: System.get_env("GEMINI_API_KEY"),
        model: System.get_env("GEMINI_MODEL", "gemini-3.8-flash"),
        thinking_level: System.get_env("GEMINI_THINKING_LEVEL", "low")

  The key never leaves the server. Output is untrusted and is validated by
  the Workouts domain (`Contract`, `Proofreading`, `FreeTextAnalysis`).
  """

  @behaviour MilosTraining.Workouts.Ports.WorkoutTextAnalyzer

  require Logger

  alias MilosTraining.Infrastructure.Workouts.GeminiPrompts
  alias MilosTraining.Workouts.Domain.WorkoutAssistant.Tools

  @endpoint "https://generativelanguage.googleapis.com/v1beta/models"
  @default_model "gemini-3.8-flash"
  # "low" keeps answers around 5–10 s; Gemini's default reasoning took 45 s+.
  @default_thinking_level "low"
  # Tool round budgets per agent: each round trip costs seconds, and the
  # prompts already carry the vocabulary, so tools are for edge cases only.
  @parser_tool_rounds 2
  @proofreader_tool_rounds 1
  # validate_draft stays available in Tools but is not offered by default: the
  # server runs the same contract on every answer and requests a repair, which
  # costs a round trip only when something is actually wrong.
  @parser_tools ~w(lookup_exercises get_timer_format convert_units)
  @proofreader_tools ~w(lookup_exercises convert_units)

  @impl true
  def parse(text, options) do
    locale = Map.get(options, :locale, "en")

    turns =
      case Map.get(options, :repair) do
        %{previous: previous, violations: violations} ->
          [
            user_turn(text),
            %{role: "model", parts: [%{text: Jason.encode!(previous)}]},
            user_turn(GeminiPrompts.repair(previous, violations))
          ]

        _first_attempt ->
          [user_turn(text)]
      end

    run(GeminiPrompts.parser(locale), turns, @parser_tools, %{
      source: text,
      agent: "parser",
      max_rounds: @parser_tool_rounds
    })
  end

  @impl true
  def proofread(text, options) do
    locale = Map.get(options, :locale, "en")

    run(GeminiPrompts.proofreader(locale), [user_turn(text)], @proofreader_tools, %{
      source: text,
      agent: "proofreader",
      max_rounds: @proofreader_tool_rounds
    })
  end

  ## Agent loop

  defp run(system_prompt, turns, tool_names, context) do
    config = Application.get_env(:milos_training, :gemini, [])

    if blank?(Keyword.get(config, :api_key)) do
      {:error, :analyzer_not_configured}
    else
      loop(system_prompt, turns, tool_names, context, config, 0)
    end
  end

  defp loop(system_prompt, turns, tool_names, context, config, round) do
    # Once the tool budget is spent the model must answer: tools stay declared
    # (the history references them) but calling is switched off.
    final_round = round >= context.max_rounds

    turns =
      if final_round and tool_names != [],
        do:
          turns ++ [user_turn("Stop calling tools. Answer now with the final JSON object only.")],
        else: turns

    body =
      %{
        systemInstruction: %{parts: [%{text: system_prompt}]},
        contents: turns,
        generationConfig:
          generation_config(Keyword.get(config, :thinking_level, @default_thinking_level))
      }
      |> put_tools(tool_names, final_round)

    with {:ok, content} <- post(body, config, context),
         parts = Map.get(content, "parts", []) do
      case function_calls(parts) do
        [] ->
          decode_answer(parts)

        calls when not final_round ->
          Logger.debug(
            "Workout assistant #{context.agent} tools: #{Enum.map_join(calls, ", ", & &1["name"])}"
          )

          responses =
            Enum.map(calls, fn %{"name" => name} = call ->
              result = Tools.call(name, Map.get(call, "args", %{}), context)
              %{functionResponse: %{name: name, response: result}}
            end)

          # The model turn is sent back verbatim (it carries thought signatures).
          turns = turns ++ [content, %{role: "user", parts: responses}]
          loop(system_prompt, turns, tool_names, context, config, round + 1)

        _calls_after_budget ->
          {:error, :analyzer_invalid_response}
      end
    end
  end

  defp post(body, config, context) do
    model = Keyword.get(config, :model) || @default_model

    request_options =
      [
        url: "#{@endpoint}/#{model}:generateContent",
        headers: [{"x-goog-api-key", Keyword.get(config, :api_key)}],
        json: body,
        receive_timeout: Keyword.get(config, :receive_timeout, 60_000),
        retry: :transient,
        max_retries: 1
      ]
      |> Keyword.merge(Keyword.get(config, :req_options, []))

    case Req.post(request_options) do
      {:ok, %Req.Response{status: 200, body: %{"candidates" => [%{"content" => content} | _]}}} ->
        {:ok, content}

      {:ok, %Req.Response{status: 200}} ->
        {:error, :analyzer_invalid_response}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning(
          "Gemini #{context.agent} failed with HTTP #{status}: #{inspect(body, limit: 5)}"
        )

        {:error, :analyzer_unavailable}

      {:error, exception} ->
        Logger.warning("Gemini #{context.agent} failed: #{Exception.message(exception)}")
        {:error, :analyzer_unavailable}
    end
  end

  defp put_tools(body, [], _final_round), do: body

  defp put_tools(body, names, final_round) do
    mode = if final_round, do: "NONE", else: "AUTO"

    body
    |> Map.put(:tools, [%{functionDeclarations: Tools.declarations(names)}])
    |> Map.put(:toolConfig, %{functionCallingConfig: %{mode: mode}})
  end

  # JSON mode with the schema in the instructions: Gemini's constrained
  # `responseSchema` decoding returned truncated, degenerate objects for this
  # deeply optional schema, while plain JSON mode follows it well.
  defp generation_config(thinking_level) do
    base = %{temperature: 0.1, responseMimeType: "application/json"}

    if blank?(thinking_level),
      do: base,
      else: Map.put(base, :thinkingConfig, %{thinkingLevel: thinking_level})
  end

  defp function_calls(parts) do
    parts
    |> Enum.map(&Map.get(&1, "functionCall"))
    |> Enum.filter(&is_map/1)
  end

  defp decode_answer(parts) do
    text =
      parts
      |> Enum.reject(&Map.get(&1, "thought"))
      |> Enum.map_join("", &Map.get(&1, "text", ""))

    case decode_json(text) do
      {:ok, %{} = decoded} ->
        {:ok, decoded}

      _other ->
        Logger.warning(
          "Gemini answer was not a JSON object: #{inspect(Enum.map(parts, &Map.keys/1))} #{String.slice(text, 0, 300)}"
        )

        {:error, :analyzer_invalid_response}
    end
  end

  # Tolerates code fences or prose around the object.
  defp decode_json(text) do
    trimmed = text |> String.trim() |> String.replace(~r/^```(?:json)?\s*|\s*```$/u, "")

    case Jason.decode(trimmed) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, _reason} ->
        with [object] <- Regex.run(~r/\{.*\}/su, trimmed),
             do: Jason.decode(object),
             else: (_ -> :error)
    end
  end

  defp user_turn(text), do: %{role: "user", parts: [%{text: text}]}

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false
end
