defmodule Palee.Email.Domain.SendingPolicy do
  @moduledoc """
  Budgets and throttles of the outbox (ADR-203), as pure decisions over
  counts the store reads.

  - **Categories.** `security` (password reset, sign-in alerts, email
    change), `account` (verify email, account notices) and `transactional`
    (everything a business sends: invoices, invitations, receipts).
  - **Per recipient and kind.** A kind may go to one address at most
    `max_per_day` times in a rolling 24 hours, and not again within
    `min_interval_seconds` of the last one. Each template may set its own
    (`Palee.Email.Template.throttle/0`); otherwise its category's default.
  - **Global daily budget.** The provider's free plan allows 300 emails a
    UTC day, so non-security mail stops at `daily_budget` (default 280) and
    is *deferred* to the next UTC day, never dropped. Security mail keeps
    going past the budget until `hard_cap` (default 295), so a password
    reset still arrives on a busy day; past the cap it is refused at enqueue
    (a link that arrives tomorrow is useless) and deferred if already queued.
  """

  @type category :: :security | :account | :transactional
  @type throttle :: %{min_interval_seconds: non_neg_integer(), max_per_day: pos_integer()}
  @type budget :: %{daily_budget: non_neg_integer(), hard_cap: non_neg_integer()}

  @categories [:security, :account, :transactional]

  @default_throttles %{
    security: %{min_interval_seconds: 60, max_per_day: 10},
    account: %{min_interval_seconds: 60, max_per_day: 10},
    transactional: %{min_interval_seconds: 0, max_per_day: 20}
  }

  @default_budget %{daily_budget: 280, hard_cap: 295}

  @doc "The categories, most urgent first."
  def categories, do: @categories

  @doc "A category from its stored name, or `:error`."
  def category(category) when category in @categories, do: {:ok, category}

  def category(name) when is_binary(name) do
    case Enum.find(@categories, &(Atom.to_string(&1) == name)) do
      nil -> :error
      category -> {:ok, category}
    end
  end

  def category(_other), do: :error

  @doc "The throttle a kind gets when its template sets none."
  def default_throttle(category), do: Map.fetch!(@default_throttles, category)

  @doc "The budget used when config sets none."
  def default_budget, do: @default_budget

  @doc """
  Whether one more `kind` email may go to the address, given what was sent
  (or queued) to it in the last 24 hours: `count` and the `last_at` of the
  newest one.
  """
  @spec throttle(throttle(), %{count: non_neg_integer(), last_at: DateTime.t() | nil}, DateTime.t()) ::
          :ok | {:error, :throttled}
  def throttle(%{min_interval_seconds: interval, max_per_day: max}, recent, %DateTime{} = now) do
    cond do
      recent.count >= max -> {:error, :throttled}
      too_soon?(recent.last_at, interval, now) -> {:error, :throttled}
      true -> :ok
    end
  end

  defp too_soon?(nil, _interval, _now), do: false
  defp too_soon?(_last_at, 0, _now), do: false
  defp too_soon?(last_at, interval, now), do: DateTime.diff(now, last_at) < interval

  @doc """
  The decision when an email is enqueued, from the number already sent this
  UTC day: queue it now, queue it for the next UTC day, or (security mail
  past the hard cap) refuse it.
  """
  @spec on_enqueue(category(), non_neg_integer(), budget(), DateTime.t()) ::
          :queue | {:defer, DateTime.t()} | {:error, :over_budget}
  def on_enqueue(category, sent_today, budget, now) do
    case on_send(category, sent_today, budget, now) do
      :send -> :queue
      {:defer, _until} when category == :security -> {:error, :over_budget}
      deferred -> deferred
    end
  end

  @doc "The decision when a queued email is about to be handed to the provider."
  @spec on_send(category(), non_neg_integer(), budget(), DateTime.t()) ::
          :send | {:defer, DateTime.t()}
  def on_send(:security, sent_today, %{hard_cap: cap}, now),
    do: if(sent_today < cap, do: :send, else: {:defer, next_day(now)})

  def on_send(_category, sent_today, %{daily_budget: budget}, now),
    do: if(sent_today < budget, do: :send, else: {:defer, next_day(now)})

  @doc "The start of `now`'s UTC day, from which the daily budget counts."
  def day_start(%DateTime{} = now),
    do: DateTime.new!(DateTime.to_date(DateTime.shift_zone!(now, "Etc/UTC")), ~T[00:00:00.000000])

  @doc "The start of the next UTC day, plus a minute so the provider's day has turned too."
  def next_day(%DateTime{} = now),
    do: now |> day_start() |> DateTime.add(1, :day) |> DateTime.add(60, :second)
end
