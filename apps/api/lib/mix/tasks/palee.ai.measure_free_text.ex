defmodule Mix.Tasks.Palee.Ai.MeasureFreeText do
  use Mix.Task

  @shortdoc "Measures the model usage and cost of free-text workout analyses (ADR-152)"

  @moduledoc """
  Runs the real free-text workout analysis (structure, proofreader, parser,
  tool rounds and repairs, exactly as the coach's "Analyze" button does) on
  sample workouts several times, and reports what each run cost from the
  token usage Gemini returns with every call.

      mix palee.ai.measure_free_text [options] FILE...

  Each FILE holds one or more sample workouts separated by a line of three or
  more dashes (`---`). Without FILE the bundled samples in
  `bench/free_text_workouts.txt` are used.

  Options:

    * `--runs N` – analyses per sample (default 5);
    * `--locale CODE` – the coach's language (default `el`);
    * `--priced-at YYYY-MM-DD` – price every call at the list price of that
      day instead of the day it was made (e.g. `2027-01-01`);
    * `--pause-ms N` – wait between runs (default 0);
    * `--out PATH` – also write every run and every call as JSON.

  Needs `GEMINI_API_KEY` (and optionally `GEMINI_MODEL`,
  `GEMINI_PARSER_THINKING_LEVEL`, …) in the environment, exactly like the
  server. Nothing is written to the database: the runs are not made for a gym.

  For each sample it prints every run (calls, input / cached / output /
  thinking tokens, cost, wall time) and the mean, sample standard deviation
  and standard error of the mean (sd / √n) of each measure, then the same
  over all runs of all samples.
  """

  alias Palee.AiUsage
  alias Palee.AiUsage.Domain.{PriceList, SampleStatistics, TokenUsage}
  alias Palee.Workouts

  @default_samples "bench/free_text_workouts.txt"
  @separator ~r/^\s*-{3,}\s*$/m
  @handler_id "palee-ai-measure-free-text"
  @measures [
    :cost_usd,
    :total_tokens,
    :input_tokens,
    :cached_input_tokens,
    :output_tokens,
    :thinking_tokens,
    :calls,
    :wall_seconds
  ]

  @switches [
    runs: :integer,
    locale: :string,
    priced_at: :string,
    pause_ms: :integer,
    out: :string
  ]

  @impl Mix.Task
  def run(args) do
    {options, files, invalid} = OptionParser.parse(args, strict: @switches)
    if invalid != [], do: Mix.raise("Unknown options: #{inspect(invalid)}")

    Mix.Task.run("app.config")
    {:ok, _apps} = Application.ensure_all_started([:telemetry, :req])
    ensure_configured!()

    runs = Keyword.get(options, :runs, 5)
    if runs < 1, do: Mix.raise("--runs must be at least 1")

    priced_at = parse_date(Keyword.get(options, :priced_at))
    samples = load_samples(if files == [], do: [@default_samples], else: files)
    table = :ets.new(:ai_measurements, [:bag, :public])

    :ok =
      :telemetry.attach(
        @handler_id,
        AiUsage.generation_event(),
        &__MODULE__.handle_event/4,
        table
      )

    try do
      header(samples, runs, priced_at)

      results =
        Enum.map(samples, fn sample ->
          measured =
            Enum.map(1..runs, fn run ->
              if run > 1, do: Process.sleep(Keyword.get(options, :pause_ms, 0))
              measure(sample, run, Keyword.get(options, :locale, "el"), table, priced_at)
            end)

          report_sample(sample, measured)
          %{sample: sample, runs: measured, statistics: statistics(measured)}
        end)

      overall = statistics(Enum.flat_map(results, & &1.runs))
      report_overall(overall, length(results) * runs)
      write_json(Keyword.get(options, :out), results, overall, priced_at)
    after
      :telemetry.detach(@handler_id)
    end
  end

  @doc false
  def handle_event(_event, measurements, metadata, table) do
    if operation_id = Map.get(metadata, :operation_id),
      do: :ets.insert(table, {operation_id, measurements, metadata})
  end

  defp measure(sample, run, locale, table, priced_at) do
    operation_id = Ecto.UUID.generate()
    started = System.monotonic_time(:millisecond)

    outcome =
      Workouts.analyze_free_text(sample.text, %{
        locale: locale,
        metering: %{operation_id: operation_id}
      })

    wall_ms = System.monotonic_time(:millisecond) - started
    calls = table |> :ets.lookup(operation_id) |> Enum.map(&call_row(&1, priced_at))
    usage = calls |> Enum.map(&TokenUsage.from_map/1) |> TokenUsage.sum()
    cost = calls |> Enum.map(& &1.cost_nano_usd) |> Enum.reject(&is_nil/1) |> Enum.sum()

    row =
      usage
      |> TokenUsage.to_map()
      |> Map.merge(%{
        run: run,
        operation_id: operation_id,
        status: status(outcome),
        repair_attempts: repair_attempts(outcome),
        calls: length(calls),
        calls_by_agent: Enum.frequencies_by(calls, & &1.agent),
        unpriced_calls: Enum.count(calls, &is_nil(&1.cost_nano_usd)),
        total_tokens: TokenUsage.total(usage),
        cost_nano_usd: cost,
        cost_usd: PriceList.to_usd(cost),
        wall_seconds: wall_ms / 1000,
        call_details: calls
      })

    Mix.shell().info(run_line(row))
    row
  end

  defp call_row({_operation_id, measurements, metadata}, priced_at) do
    usage = TokenUsage.from_map(measurements)
    date = priced_at || DateTime.to_date(metadata.occurred_at)

    cost =
      case PriceList.cost(usage, metadata.model, date) do
        {:ok, nano} -> nano
        {:error, :unpriced_model} -> nil
      end

    usage
    |> TokenUsage.to_map()
    |> Map.merge(%{
      agent: metadata[:agent],
      model: metadata[:model],
      model_version: metadata[:model_version],
      duration_ms: measurements[:duration_ms],
      occurred_at: metadata[:occurred_at],
      cost_nano_usd: cost
    })
  end

  defp status({:ok, _result}), do: "ok"
  defp status({:error, reason}), do: "error: #{reason}"

  defp repair_attempts({:ok, %{"quality" => %{"repair_attempts" => attempts}}}), do: attempts
  defp repair_attempts(_outcome), do: nil

  defp statistics(runs) do
    Map.new(@measures, fn measure ->
      {measure, SampleStatistics.describe(Enum.map(runs, &Map.fetch!(&1, measure)))}
    end)
  end

  ## Output

  defp header(samples, runs, priced_at) do
    config = Application.get_env(:palee, :gemini, [])

    Mix.shell().info("""
    Free-text workout analysis: #{length(samples)} samples × #{runs} runs
    model #{Keyword.get(config, :model)}, thinking #{Keyword.get(config, :thinking_level)} (parser #{Keyword.get(config, :parser_thinking_level)})
    prices: #{if priced_at, do: "list prices of #{priced_at}", else: "list prices of the day of each call"}
    """)
  end

  defp run_line(row) do
    agents =
      Enum.map_join(Enum.sort(row.calls_by_agent), " ", fn {agent, n} -> "#{agent}×#{n}" end)

    "  run #{row.run}: #{row.status}, #{row.calls} calls (#{agents}), " <>
      "in #{row.input_tokens} + cached #{row.cached_input_tokens}, out #{row.output_tokens} + " <>
      "thinking #{row.thinking_tokens} = #{row.total_tokens} tokens, " <>
      "$#{usd(row.cost_usd)}, #{Float.round(row.wall_seconds, 1)} s" <>
      if(row.unpriced_calls > 0, do: " (#{row.unpriced_calls} calls unpriced)", else: "")
  end

  defp report_sample(sample, runs) do
    Mix.shell().info(
      "\n#{sample.name}: #{sample.title}\n" <> statistics_lines(statistics(runs)) <> "\n"
    )
  end

  defp report_overall(overall, count) do
    Mix.shell().info("\nAll #{count} runs\n" <> statistics_lines(overall))

    if mean = overall.cost_usd.mean do
      Mix.shell().info("  ≈ $#{usd(mean * 1000)} per 1,000 analyses")
    end
  end

  defp statistics_lines(statistics) do
    Enum.map_join(@measures, "\n", fn measure ->
      %{n: n, mean: mean, sd: sd, se: se, min: min, max: max} = Map.fetch!(statistics, measure)
      format = if measure == :cost_usd, do: &usd/1, else: &number/1

      "  #{String.pad_trailing(to_string(measure), 20)} mean #{format.(mean)} ± #{format.(se)} (SE), " <>
        "sd #{format.(sd)}, min #{format.(min)}, max #{format.(max)}, n #{n}"
    end)
  end

  defp usd(nil), do: "–"
  defp usd(value), do: :erlang.float_to_binary(value / 1, decimals: 6)

  defp number(nil), do: "–"
  defp number(value) when is_integer(value), do: Integer.to_string(value)
  defp number(value), do: :erlang.float_to_binary(value / 1, decimals: 1)

  defp write_json(nil, _results, _overall, _priced_at), do: :ok

  defp write_json(path, results, overall, priced_at) do
    config = Application.get_env(:palee, :gemini, [])

    document = %{
      measured_at: DateTime.utc_now(),
      model: Keyword.get(config, :model),
      thinking_level: Keyword.get(config, :thinking_level),
      parser_thinking_level: Keyword.get(config, :parser_thinking_level),
      priced_at: priced_at,
      samples:
        Enum.map(results, fn result ->
          %{
            name: result.sample.name,
            title: result.sample.title,
            characters: String.length(result.sample.text),
            runs: result.runs,
            statistics: result.statistics
          }
        end),
      overall: overall
    }

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode_to_iodata!(document, pretty: true))
    Mix.shell().info("\nWrote #{path}")
  end

  ## Input

  defp load_samples(files) do
    files
    |> Enum.flat_map(fn file ->
      unless File.regular?(file), do: Mix.raise("No such sample file: #{file}")

      file
      |> File.read!()
      |> String.split(@separator)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.with_index(1)
      |> Enum.map(fn {text, index} ->
        %{
          name: "#{Path.basename(file)}##{index}",
          title: text |> String.split("\n", parts: 2) |> hd() |> String.slice(0, 60),
          text: text
        }
      end)
    end)
    |> case do
      [] -> Mix.raise("No sample workouts found in #{Enum.join(files, ", ")}")
      samples -> samples
    end
  end

  defp parse_date(nil), do: nil

  defp parse_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> Mix.raise("--priced-at must be a date like 2027-01-01")
    end
  end

  defp ensure_configured! do
    key = :palee |> Application.get_env(:gemini, []) |> Keyword.get(:api_key)

    if not is_binary(key) or String.trim(key) == "" do
      Mix.raise("GEMINI_API_KEY is not set: export it (or run inside the api container) first")
    end

    analyzer = Application.fetch_env!(:palee, :workout_text_analyzer)

    unless analyzer == Palee.Infrastructure.Workouts.GeminiWorkoutTextAnalyzer do
      Mix.raise("MIX_ENV=#{Mix.env()} uses #{inspect(analyzer)}; run with MIX_ENV=dev or prod")
    end
  end
end
