defmodule Palee.Partners.Domain.ReportPolicy do
  @moduledoc """
  Reporting a person in Partners and the Palee team's decision (ADR-280,
  ADR-169 §5–§6). Pure.

  A person reports another with a reason and an optional note of at most
  500 characters; reporting also blocks. The Palee team decides once per
  reported person: `suspend` closes every open report on them as
  `actioned` and suspends them (profile off, verification `suspended`,
  matches end with `suspended`, their sponsors get a 60-day penalty);
  `dismiss` closes them as `dismissed`.
  """

  @reasons ~w(unsafe fake minor harassment other)
  @statuses ~w(open actioned dismissed)
  @decisions ~w(suspend dismiss)
  @note_max 500

  def reasons, do: @reasons
  def statuses, do: @statuses
  def decisions, do: @decisions
  def note_max, do: @note_max

  @doc "A report's attributes from a request."
  def normalize(reporter_id, params) do
    with {:ok, target_id} <- target(params),
         true <- target_id != reporter_id || {:error, :cannot_report_self},
         {:ok, reason} <- reason(fetch(params, :reason)),
         {:ok, note} <- note(fetch(params, :note)) do
      {:ok, %{reporter_id: reporter_id, target_id: target_id, reason: reason, note: note}}
    end
  end

  @doc "A decision of the Palee team from a request."
  def normalize_decision(params) do
    with {:ok, decision} <- decision(fetch(params, :decision)),
         {:ok, note} <- note(fetch(params, :note)) do
      {:ok, %{decision: decision, note: note}}
    end
  end

  @doc "The changes that close an open report with a decision."
  def decision_changes(%{status: "open"}, decision, decided_by_id, note, now)
      when decision in @decisions do
    {:ok,
     %{
       status: status(decision),
       decided_by_id: decided_by_id,
       decided_at: now,
       decision_note: note
     }}
  end

  def decision_changes(%{status: "open"}, _decision, _by, _note, _now),
    do: {:error, :invalid_partner_decision}

  def decision_changes(_report, _decision, _by, _note, _now),
    do: {:error, :partner_report_decided}

  @doc "Whether a decision suspends the reported person."
  def suspends?("suspend"), do: true
  def suspends?(_decision), do: false

  @doc "What a suspension does to the person's profile; matches end with this reason."
  def suspension_profile_changes, do: %{active: false}
  def suspension_end_reason, do: "suspended"

  defp status("suspend"), do: "actioned"
  defp status("dismiss"), do: "dismissed"

  defp target(params) do
    case Ecto.UUID.cast(fetch(params, :target_id) || "") do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  defp reason(reason) when reason in @reasons, do: {:ok, reason}
  defp reason(_reason), do: {:error, :invalid_partner_report_reason}

  defp decision(decision) when decision in @decisions, do: {:ok, decision}
  defp decision(_decision), do: {:error, :invalid_partner_decision}

  defp note(nil), do: {:ok, nil}

  defp note(text) when is_binary(text) do
    case String.trim(text) do
      "" ->
        {:ok, nil}

      trimmed ->
        if String.length(trimmed) <= @note_max,
          do: {:ok, trimmed},
          else: {:error, :partner_report_note_too_long}
    end
  end

  defp note(_text), do: {:error, :partner_report_note_too_long}

  defp fetch(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, Atom.to_string(key)))

  defp fetch(_params, _key), do: nil
end
