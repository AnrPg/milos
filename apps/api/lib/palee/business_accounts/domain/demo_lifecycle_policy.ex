defmodule Palee.BusinessAccounts.Domain.DemoLifecyclePolicy do
  @moduledoc """
  ADR-184 follow-up: what happens to a demo business nobody uses.

  **Last activity** is `organizations.demo_last_active_at`: the latest sign-in
  of the business's owners and admins, and the latest console request they
  made in it (any `/api/org/:slug/...` request, which covers every change
  the business makes to itself). It is written at most once per
  `touch_interval_seconds`. Until the first touch, the demo's start counts.
  Mock people cannot sign in, and their rows are written through the owner's
  own requests, so nothing else can keep a demo alive.

  With the default thresholds:

    * after `reminder_after_days` (60) without activity the owners get one
      reminder (claimed by `demo_reminder_sent_at`, deduplicated per idle
      spell);
    * after `archive_after_days` (90), and at least the difference (30 days)
      after the reminder was claimed, the demo data and mock people are
      removed and the organization is archived. The owners' accounts stay.

  Any owner or admin activity resets the clock and withdraws the reminder
  claim. An archived demo reopens empty, from Εγώ › Ρυθμίσεις or by
  signing up or asking for a conversion again.
  """

  @defaults %{reminder_after_days: 60, archive_after_days: 90, touch_interval_seconds: 3_600}
  @day 86_400

  @type thresholds :: %{
          reminder_after_days: pos_integer(),
          archive_after_days: pos_integer(),
          touch_interval_seconds: pos_integer()
        }
  @type candidate :: %{
          required(:last_active_at) => DateTime.t(),
          required(:reminder_sent_at) => DateTime.t() | nil,
          optional(any()) => any()
        }

  @doc "The defaults, overridden by `overrides` (keyword list or map) where valid."
  @spec thresholds(keyword() | map()) :: thresholds()
  def thresholds(overrides \\ []) do
    merged =
      Enum.reduce(Map.new(overrides), @defaults, fn
        {key, value}, acc when is_map_key(@defaults, key) and is_integer(value) and value > 0 ->
          Map.put(acc, key, value)

        _ignored, acc ->
          acc
      end)

    if merged.archive_after_days > merged.reminder_after_days,
      do: merged,
      else: %{merged | archive_after_days: merged.reminder_after_days + 1}
  end

  @doc "Activity before this instant makes a demo due for its reminder."
  @spec reminder_cutoff(DateTime.t(), thresholds()) :: DateTime.t()
  def reminder_cutoff(now, %{reminder_after_days: days}), do: DateTime.add(now, -days * @day)

  @doc "Activity before this instant makes a demo due for archiving."
  @spec archive_cutoff(DateTime.t(), thresholds()) :: DateTime.t()
  def archive_cutoff(now, %{archive_after_days: days}), do: DateTime.add(now, -days * @day)

  @doc """
  A reminder claimed before this instant has given the owners their notice;
  so a demo found idle for 90 days at once still gets its 30 days.
  """
  @spec reminded_cutoff(DateTime.t(), thresholds()) :: DateTime.t()
  def reminded_cutoff(now, thresholds), do: DateTime.add(now, -notice_days(thresholds) * @day)

  @doc "The days between the reminder and archiving."
  @spec notice_days(thresholds()) :: pos_integer()
  def notice_days(%{reminder_after_days: reminder, archive_after_days: archive}),
    do: archive - reminder

  @doc "What the sweep does with an idle demo: `:archive`, `:remind` or `:keep`."
  @spec stage(candidate(), DateTime.t(), thresholds()) :: :archive | :remind | :keep
  def stage(%{last_active_at: last_active_at} = candidate, now, thresholds) do
    reminder_sent_at = Map.get(candidate, :reminder_sent_at)

    cond do
      before?(last_active_at, archive_cutoff(now, thresholds)) and
          before?(reminder_sent_at, reminded_cutoff(now, thresholds)) ->
        :archive

      is_nil(reminder_sent_at) and before?(last_active_at, reminder_cutoff(now, thresholds)) ->
        :remind

      true ->
        :keep
    end
  end

  @doc "The reminder's dedupe key: one per demo and idle spell."
  @spec reminder_dedupe_key(String.t(), DateTime.t()) :: String.t()
  def reminder_dedupe_key(organization_id, %DateTime{} = last_active_at),
    do: "business_demo_idle:#{organization_id}:#{DateTime.to_unix(last_active_at, :microsecond)}"

  @doc "The day the demo is archived if nobody comes back, as an ISO date."
  @spec archive_on(DateTime.t(), thresholds()) :: Date.t()
  def archive_on(%DateTime{} = last_active_at, %{archive_after_days: days}),
    do: last_active_at |> DateTime.add(days * @day) |> DateTime.to_date()

  defp before?(nil, _cutoff), do: false
  defp before?(%DateTime{} = at, cutoff), do: DateTime.compare(at, cutoff) == :lt
end
