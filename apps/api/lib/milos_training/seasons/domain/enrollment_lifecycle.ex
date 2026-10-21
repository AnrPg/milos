defmodule MilosTraining.Seasons.Domain.EnrollmentLifecycle do
  @moduledoc """
  The steps a season enrollment may take (ADR-167). Pure: callers get the
  changes to write, or `{:error, :invalid_season_transition}`.

      (none) ─request─▶ requested ─confirm─▶ active ─complete─▶ completed
                           │  ▲                 │
                           │  └─promote─ waitlisted (full when asked)
                           ├─decline─▶ declined
                           └─cancel──▶ cancelled (also from waitlisted and active)

  A declined or cancelled member may ask again; the same row returns to
  `requested` or `waitlisted`.
  """

  @statuses ~w(requested waitlisted active declined cancelled completed)
  @open ~w(requested waitlisted)
  @holding ~w(requested active)

  @steps %{
    confirm: {["requested", "waitlisted"], "active"},
    decline: {["requested", "waitlisted"], "declined"},
    cancel: {["requested", "waitlisted", "active"], "cancelled"},
    promote: {["waitlisted"], "requested"},
    complete: {["active"], "completed"}
  }

  def statuses, do: @statuses
  def open_statuses, do: @open

  @doc "Statuses that hold one of the season's places."
  def holding_statuses, do: @holding

  @doc "Whether the member may ask (again) from this status; nil is no row yet."
  def can_request?(nil), do: true
  def can_request?(status), do: status in ["declined", "cancelled"]

  @doc "The changes a (re-)request writes: `status` is `requested` or `waitlisted`."
  def request(status, %DateTime{} = now) when status in ["requested", "waitlisted"] do
    %{
      status: status,
      requested_at: now,
      decided_at: nil,
      decided_by_id: nil,
      decline_reason: nil,
      cancelled_at: nil,
      completed_at: nil,
      package_subscription_id: nil
    }
  end

  @doc "The changes for `step` at `now`. `opts`: `:by` (who decided), `:reason`."
  def transition(%{status: from}, step, %DateTime{} = now, opts \\ []) do
    case Map.fetch(@steps, step) do
      {:ok, {allowed, to}} ->
        if from in allowed,
          do: {:ok, Map.put(stamp(step, now, opts), :status, to)},
          else: {:error, :invalid_season_transition}

      :error ->
        {:error, :invalid_season_transition}
    end
  end

  defp stamp(:confirm, now, opts),
    do: %{decided_at: now, decided_by_id: opts[:by]}

  defp stamp(:decline, now, opts),
    do: %{decided_at: now, decided_by_id: opts[:by], decline_reason: opts[:reason]}

  defp stamp(:cancel, now, _opts), do: %{cancelled_at: now}
  defp stamp(:promote, _now, _opts), do: %{}
  defp stamp(:complete, now, _opts), do: %{completed_at: now}
end
