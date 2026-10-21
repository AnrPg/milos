defmodule Palee.Infrastructure.Ai.AnthropicScalingAdvisor do
  @moduledoc """
  The scaling advisor on the Claude API (ADR-174): one Messages API call per
  athlete and workout, with a JSON-schema constrained answer
  (`output_config.format`) at low effort.

  The gym's own key comes in `options.api_key` (no platform key fallback).
  The model is the gym's override or the platform default
  (`ANTHROPIC_SCALING_MODEL`, `claude-sonnet-5-5`). On models that support it
  the request opts into server-side refusal fallbacks (`fallbacks: "default"`),
  so a safety decline on the main model is retried on a fallback model in the
  same call. Every answered call is metered through `AiUsage` (ADR-152),
  whatever its content.

  Errors: 401/403 → `:advisor_key_rejected`; 429, 5xx, timeouts →
  `:advisor_unavailable`; a refusal → `:advisor_refused`; an answer that is
  not the expected JSON → `:advisor_invalid_response`.
  """

  @behaviour Palee.Scaling.Ports.ScalingAdvisor

  require Logger

  alias Palee.AiUsage

  @endpoint "https://api.anthropic.com/v1/messages"
  @version "2023-06-01"
  @fallback_beta "server-side-fallback-2026-07-01"
  @default_model "claude-sonnet-5-5"
  @fallback_models ~w(claude-sonnet-5-5 claude-opus-5-5 claude-opus-5 claude-fable-5-1)
  @max_tokens 8_000

  @system """
  You help a gym coach adapt one programmed workout for one athlete who has
  active injuries. The coach reviews every suggestion before the athlete sees
  anything; you never speak to the athlete directly.

  Rules:
  - Propose a change only for a movement that the injuries plausibly affect.
    Leave every other movement out. If nothing needs to change, return an
    empty "items" list and "scale_level": null.
  - Prefer the gentlest change that keeps the workout's intent: a lighter
    load, fewer reps or a shorter range first; a substitution that spares the
    injured area next; "skip" only when no safe option exists.
  - "exercise_id" must be one of the ids given in the workout. "change" is
    one of: substitute (name the replacement movement in "suggested"), load
    (the new load), reps (the new reps or time), other (any other
    prescription change), skip ("suggested": null).
  - "scale_level" is the slug of one of the gym's scale levels when the whole
    workout should run at that level, else null.
  - "reason" is one short, neutral sentence a coach can show the athlete.
    No diagnosis, no medical claims, no promises about healing, no blame.
  - "summary" is one or two short sentences for the coach.
  - Write "summary", "reason" and "suggested" in the language given as
    "locale" (el = Greek).
  - Training limitations written by the gym take precedence over your own
    judgement. "flagged_movements" lists what a deterministic rule already
    marks as caution or avoid; use it as a hint, not as the answer.
  """

  @schema %{
    type: "object",
    additionalProperties: false,
    required: ["summary", "scale_level", "items"],
    properties: %{
      summary: %{type: "string"},
      scale_level: %{anyOf: [%{type: "string"}, %{type: "null"}]},
      items: %{
        type: "array",
        items: %{
          type: "object",
          additionalProperties: false,
          required: ["exercise_id", "change", "suggested", "reason"],
          properties: %{
            exercise_id: %{type: "string"},
            change: %{type: "string", enum: ["substitute", "load", "reps", "other", "skip"]},
            suggested: %{anyOf: [%{type: "string"}, %{type: "null"}]},
            reason: %{type: "string"}
          }
        }
      }
    }
  }

  def default_model, do: @default_model

  @impl true
  def suggest(input, options) do
    case Map.get(options, :api_key) do
      key when is_binary(key) and key != "" ->
        model = Map.get(options, :model) || configured_model()
        request(key, model, input, AiUsage.metering(options))

      _missing ->
        {:error, :advisor_not_configured}
    end
  end

  @doc "The request body (exposed for tests and the measurement task)."
  def body(model, input) do
    %{
      model: model,
      max_tokens: @max_tokens,
      system: @system,
      messages: [%{role: "user", content: Jason.encode!(input)}],
      output_config: %{effort: "low", format: %{type: "json_schema", schema: @schema}}
    }
    |> maybe_fallbacks(model)
  end

  defp maybe_fallbacks(body, model) do
    if model in @fallback_models, do: Map.put(body, :fallbacks, "default"), else: body
  end

  defp request(api_key, model, input, metering) do
    started = System.monotonic_time(:millisecond)

    response =
      Req.post(
        [
          url: @endpoint,
          json: body(model, input),
          headers: headers(api_key, model),
          receive_timeout: 90_000,
          retry: false
        ]
        |> Keyword.merge(req_options())
      )

    meter(response, model, metering, System.monotonic_time(:millisecond) - started)
    interpret(response)
  end

  defp headers(api_key, model) do
    base = [{"x-api-key", api_key}, {"anthropic-version", @version}]
    if model in @fallback_models, do: [{"anthropic-beta", @fallback_beta} | base], else: base
  end

  defp interpret({:ok, %Req.Response{status: 200, body: %{"stop_reason" => "refusal"}}}),
    do: {:error, :advisor_refused}

  defp interpret({:ok, %Req.Response{status: 200, body: %{"content" => content} = body}})
       when is_list(content) do
    with %{"text" => text} <- Enum.find(content, &(Map.get(&1, "type") == "text")),
         {:ok, %{} = decoded} <- Jason.decode(text) do
      {:ok, decoded}
    else
      _other ->
        Logger.info(
          "scaling_advisor_invalid_response stop_reason=#{inspect(body["stop_reason"])}"
        )

        {:error, :advisor_invalid_response}
    end
  end

  defp interpret({:ok, %Req.Response{status: status}}) when status in [401, 403],
    do: {:error, :advisor_key_rejected}

  defp interpret({:ok, %Req.Response{status: status}}) do
    Logger.info("scaling_advisor_unavailable status=#{status}")
    {:error, :advisor_unavailable}
  end

  defp interpret({:error, reason}) do
    Logger.info("scaling_advisor_unavailable reason=#{inspect(reason)}")
    {:error, :advisor_unavailable}
  end

  # ADR-152: every answered call is billed, whatever its text.
  defp meter({:ok, %Req.Response{status: 200, body: %{} = body}}, model, metering, duration_ms) do
    case AiUsage.token_usage_from_anthropic(Map.get(body, "usage")) do
      nil ->
        :ok

      usage ->
        AiUsage.report_generation(
          usage,
          duration_ms,
          metering
          |> AiUsage.metering_context()
          |> Map.merge(%{
            provider: "anthropic",
            model: model,
            model_version: Map.get(body, "model"),
            agent: "scaling",
            occurred_at: DateTime.utc_now()
          })
        )
    end
  end

  defp meter(_response, _model, _metering, _duration_ms), do: :ok

  defp config, do: Application.get_env(:palee, :anthropic, [])
  defp configured_model, do: Keyword.get(config(), :scaling_model) || @default_model
  defp req_options, do: Keyword.get(config(), :req_options, [])
end
