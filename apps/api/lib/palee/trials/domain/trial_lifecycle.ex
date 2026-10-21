defmodule Palee.Trials.Domain.TrialLifecycle do
  @moduledoc """
  The steps a trial may take (ADR-144). Pure: callers get the changes to
  write, or `{:error, :invalid_trial_transition}`.

      requested ─accept─▶ booked ─▶ attended ─▶ converted
          │                 │  ▲        │           ▲
          ├─decline─▶ declined   └── no_show ───────┘
          ├─cancel──▶ cancelled (also from booked)
          └─expire──▶ expired (no answer before the class)

  Attendance can be corrected (attended ⇄ no_show), and someone who joins
  before their trial class converts straight from booked.
  """

  @statuses ~w(requested booked declined cancelled expired attended no_show converted)
  @open ~w(requested booked)

  @steps %{
    accept: {["requested"], "booked"},
    decline: {["requested"], "declined"},
    cancel: {["requested", "booked"], "cancelled"},
    expire: {["requested"], "expired"},
    attend: {["booked", "no_show"], "attended"},
    no_show: {["booked", "attended"], "no_show"},
    convert: {["booked", "attended", "no_show"], "converted"}
  }

  def statuses, do: @statuses
  def open_statuses, do: @open
  def steps, do: Map.keys(@steps)

  @doc "Whether a trial in this status still holds (or waits for) a seat."
  def open?(status), do: status in @open

  @doc """
  The changes for `step` at `now`. `opts`: `:by` (who decided), `:reason`
  (a decline's reason shown to the person).
  """
  def transition(%{status: from}, step, %DateTime{} = now, opts \\ []) do
    case Map.fetch(@steps, step) do
      {:ok, {allowed, to}} ->
        if from in allowed,
          do: {:ok, Map.put(stamp(step, now, opts), :status, to)},
          else: {:error, :invalid_trial_transition}

      :error ->
        {:error, :invalid_trial_transition}
    end
  end

  defp stamp(:accept, now, opts), do: %{decided_at: now, decided_by_id: opts[:by]}

  defp stamp(:decline, now, opts),
    do: %{decided_at: now, decided_by_id: opts[:by], decline_reason: opts[:reason]}

  defp stamp(:cancel, now, _opts), do: %{cancelled_at: now}
  defp stamp(:expire, now, _opts), do: %{decided_at: now}
  defp stamp(:attend, now, _opts), do: %{attended_at: now}
  defp stamp(:no_show, _now, _opts), do: %{attended_at: nil}
  defp stamp(:convert, now, _opts), do: %{converted_at: now}

  @doc """
  Takes back an `attend` step whose check-in was undone (ADR-155): the trial
  returns to the status it had before (`booked` or `no_show`). Only an
  `attended` trial goes back, so a converted one keeps its conversion.
  """
  def undo_attend(%{status: "attended"}, previous) when previous in ["booked", "no_show"],
    do: {:ok, %{status: previous, attended_at: nil}}

  def undo_attend(_request, _previous), do: {:error, :invalid_trial_transition}

  @doc """
  Whether a past trial uses up one of the person's trials at this box. A
  declined, cancelled or expired ask doesn't; a no-show does when the
  owner says so (plan open question 2).
  """
  def consumes?(status, no_show_consumes?)
  def consumes?(status, _no_show) when status in ~w(requested booked attended converted), do: true
  def consumes?("no_show", no_show_consumes?), do: no_show_consumes?
  def consumes?(_status, _no_show), do: false
end
