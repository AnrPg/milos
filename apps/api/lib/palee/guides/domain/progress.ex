defmodule Palee.Guides.Domain.Progress do
  @moduledoc """
  ADR-193: the rules of a walkthrough's progress, independent of storage.

  The web app owns the guides themselves (their steps and copy), so the
  server accepts any well-formed guide id and keeps only what it needs to
  offer a guide once, resume it and show it done everywhere:

  - `started` with the step reached, `completed` or `dismissed` («not now»);
  - a new run (starting after a finish or a dismissal, or a newer version
    of the guide) counts in `runs` and clears the old finish;
  - `completed_at` is the first finish of the current run, so replaying a
    finished guide's last step never moves it.
  """

  @statuses ~w(started completed dismissed)
  @id_format ~r/^[a-z][a-z0-9_]{1,47}$/
  @max_step 99
  @max_version 1000
  @max_guides 100

  def statuses, do: @statuses
  def max_step, do: @max_step
  def max_version, do: @max_version
  def max_guides, do: @max_guides
  def id_pattern, do: Regex.source(@id_format)

  @doc "Checks a guide id from the URL."
  def validate_id(id) when is_binary(id) do
    if Regex.match?(@id_format, id), do: :ok, else: {:error, :not_found}
  end

  def validate_id(_id), do: {:error, :not_found}

  @doc "Parses a progress change from request params into `%{status, step, version}`."
  def parse_change(params) when is_map(params) do
    status = params["status"]
    step = Map.get(params, "step", 0)
    version = Map.get(params, "version", 1)

    errors =
      []
      |> check(status in @statuses, :status, "must be one of: #{Enum.join(@statuses, ", ")}")
      |> check(
        is_integer(step) and step in 0..@max_step,
        :step,
        "must be an integer from 0 to #{@max_step}"
      )
      |> check(
        is_integer(version) and version in 1..@max_version,
        :version,
        "must be an integer from 1 to #{@max_version}"
      )

    if errors == [],
      do: {:ok, %{status: status, step: step, version: version}},
      else: {:error, Enum.reverse(errors)}
  end

  def parse_change(_params), do: {:error, [body: "must be an object"]}

  @doc """
  The stored row after `change`: `existing` is the current row as a map, or
  nil. Answers the fields to write.
  """
  def apply_change(nil, change, now) do
    %{
      version: change.version,
      status: change.status,
      step: change.step,
      runs: 1,
      started_at: now,
      completed_at: completed_at(change.status, nil, now)
    }
  end

  def apply_change(existing, change, now) do
    if new_run?(existing, change) do
      %{
        version: change.version,
        status: change.status,
        step: change.step,
        runs: existing.runs + 1,
        started_at: now,
        completed_at: completed_at(change.status, nil, now)
      }
    else
      %{
        version: max(existing.version, change.version),
        status: change.status,
        step: change.step,
        runs: existing.runs,
        started_at: existing.started_at,
        completed_at: completed_at(change.status, existing.completed_at, now)
      }
    end
  end

  @doc "Whether this person already holds the most guides they may have and `guide_id` is new."
  def over_limit?(count, existing?), do: not existing? and count >= @max_guides

  defp new_run?(existing, change) do
    change.version > existing.version or
      (change.status == "started" and existing.status in ~w(completed dismissed))
  end

  defp completed_at("completed", nil, now), do: now
  defp completed_at("completed", at, _now), do: at
  defp completed_at(_status, at, _now), do: at

  defp check(errors, true, _field, _message), do: errors
  defp check(errors, false, field, message), do: [{field, message} | errors]
end
