defmodule Palee.PersonalData.Domain.ExportPolicy do
  @moduledoc """
  ADR-267: when a person may ask for "Download my data", and how long the
  file is kept.

    * One request at a time: a pending one answers `:export_in_progress`.
    * One file a day: a request made less than `cooldown_hours/0` after the
      last one that did not fail answers `{:export_rate_limited, retry_at}`.
      A failed build does not count, so the person may simply ask again.
    * The file is kept `keep_days/0` days; its download links are
      short-lived (the object store's presigned links) and made afresh each
      time the person opens the list.
  """

  @statuses ~w(pending ready failed)
  @keep_days 7
  @cooldown_hours 24

  def statuses, do: @statuses
  def keep_days, do: @keep_days
  def cooldown_hours, do: @cooldown_hours

  @doc "`:ok`, or why a new request must wait. `exports` are the person's, any order."
  def can_request?(exports, %DateTime{} = now) when is_list(exports) do
    cond do
      Enum.any?(exports, &(&1.status == "pending")) ->
        {:error, :export_in_progress}

      retry_at = retry_at(exports, now) ->
        {:error, {:export_rate_limited, retry_at}}

      true ->
        :ok
    end
  end

  defp retry_at(exports, now) do
    exports
    |> Enum.reject(&(&1.status == "failed"))
    |> Enum.map(&DateTime.add(&1.requested_at, @cooldown_hours * 3_600, :second))
    |> Enum.filter(&(DateTime.compare(&1, now) == :gt))
    |> Enum.max(DateTime, fn -> nil end)
  end

  @doc "When a file finished at `now` stops being offered."
  def expires_at(%DateTime{} = now), do: DateTime.add(now, @keep_days * 86_400, :second)

  @doc "How the person sees an export: a ready file past its time is `expired`."
  def visible_status(%{status: "ready", expires_at: %DateTime{} = expires_at}, %DateTime{} = now) do
    if DateTime.compare(expires_at, now) == :gt, do: "ready", else: "expired"
  end

  def visible_status(%{status: status}, _now), do: status

  @doc "Whether the file may still be downloaded."
  def downloadable?(export, now), do: visible_status(export, now) == "ready"
end
