defmodule MilosTraining.Workouts.Queries.AnalyzeFreeText do
  @moduledoc """
  Reads a free-text workout with the workout assistant agents and validates
  the result against the canonical schema. Read-only: the analysis is a
  proposal; nothing is persisted until the coach publishes.

  Flow:
    1. the proofreader starts in parallel with everything below;
    2. structure first: the structure agent splits the text into sections and
       infers each section's format; the server verifies the outline against
       `FormatSchema` (known formats, verbatim evidence);
    3. the parser fills the sections, given the outline and the canonical JSON
       Schema of every format used. Without a valid outline it parses in one
       step (it still has the `get_section_schema` tool);
    4. the parser's answer is checked by the strict `Contract` (the same
       per-format schemas); on violations the parser is asked to repair it (at
       most #{2} times) and the attempt with the fewest violations wins;
    5. verified proofreading corrections are merged into the issues;
    6. `FreeTextAnalysis` normalizes everything into canonical data.

  Proofreader and structure failures never fail the analysis; a parser
  failure does.
  """

  require Logger

  alias MilosTraining.Workouts.Domain.FreeTextAnalysis
  alias MilosTraining.Workouts.Domain.WorkoutAssistant.{Contract, FormatSchema, Proofreading}

  @max_length 20_000
  @max_repairs 2
  @agent_timeout 150_000

  def call(text, options \\ %{})

  def call(text, options) when is_binary(text) do
    trimmed = String.trim(text)

    cond do
      trimmed == "" -> {:error, :text_required}
      String.length(trimmed) > @max_length -> {:error, :text_too_long}
      true -> analyze(trimmed, options)
    end
  end

  def call(_text, _options), do: {:error, :text_required}

  def max_length, do: @max_length

  defp analyze(text, options) do
    proofreading = Task.async(fn -> safely(fn -> analyzer().proofread(text, options) end) end)
    outline = infer_structure(text, options)
    options = if outline, do: Map.put(options, :outline, outline), else: options

    with {:ok, raw} <- analyzer().parse(text, options) do
      {raw, quality} = repair(text, options, raw, Contract.check(raw, text), 0)
      corrections = await_corrections(proofreading, text)

      quality =
        Map.merge(quality, %{
          "corrections" => length(corrections),
          "structure_inferred" => outline != nil
        })

      result =
        raw
        |> FreeTextAnalysis.normalize(text, corrections)
        |> Map.put("quality", quality)

      {:ok, result}
    else
      error ->
        Task.shutdown(proofreading, :brutal_kill)
        error
    end
  end

  defp infer_structure(text, options) do
    with {:ok, raw} <- analyzer().outline(text, options),
         {:ok, outline} <- FormatSchema.verify_outline(raw, text) do
      outline
    else
      {:error, violations} when is_list(violations) ->
        Logger.info("Workout structure rejected: #{length(violations)} violations")
        nil

      _failed ->
        nil
    end
  end

  defp repair(_text, _options, raw, [] = _violations, attempts),
    do: {raw, quality(attempts, [])}

  defp repair(_text, _options, raw, violations, attempts) when attempts >= @max_repairs,
    do: {raw, quality(attempts, violations)}

  defp repair(text, options, raw, violations, attempts) do
    Logger.info(
      "Workout assistant repair #{attempts + 1}: #{length(violations)} contract violations"
    )

    repair_options = Map.put(options, :repair, %{previous: raw, violations: violations})

    case analyzer().parse(text, repair_options) do
      {:ok, repaired} ->
        repaired_violations = Contract.check(repaired, text)

        if length(repaired_violations) < length(violations),
          do: repair(text, options, repaired, repaired_violations, attempts + 1),
          else: {raw, quality(attempts + 1, violations)}

      {:error, _reason} ->
        {raw, quality(attempts + 1, violations)}
    end
  end

  defp quality(attempts, violations) do
    %{"repair_attempts" => attempts, "remaining_violations" => length(violations)}
  end

  defp await_corrections(task, text) do
    case Task.yield(task, @agent_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, raw}} -> Proofreading.verify(raw, text)
      _failed_or_timed_out -> []
    end
  end

  # The proofreader is best-effort: an exception there must never take down
  # the (linked) request process.
  defp safely(fun) do
    fun.()
  rescue
    exception ->
      Logger.warning("Workout proofreader crashed: #{Exception.message(exception)}")
      {:error, :analyzer_unavailable}
  end

  defp analyzer, do: Application.fetch_env!(:milos_training, :workout_text_analyzer)
end
