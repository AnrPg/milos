defmodule MilosTraining.Insights.Domain.InsightRule do
  @moduledoc """
  One insight rule (ADR-166, vision §7.7 and §8.6). Pure.

  A rule names what it reads (`section/0`: the journal section that must be
  on, `item/0`: the wellness item that must not be hidden), states its
  minimum sample (`minimum/0`) and computes one result from the inputs the
  application gathers for the last `InsightCatalog.window_days/0` days:

    * `:today`, `:from` (the window's first day);
    * `:sessions`: `[%{at: DateTime, tz: String.t(), rpe: 1..10 | nil}]`;
    * `:pr_days`: the days a personal record was set;
    * `:days`: the wellness day summaries of the window (`DaySummary`);
    * `:cravings`: `[%{occurred_at, occurred_tz, triggers}]`;
    * `:sleep_goal_minutes`: the member's own sleep goal.

  A result is `finding/4` (enough data and a clear pattern), `no_finding/2`
  (enough data, nothing clear) or `insufficient/2`. The copy key is
  `insights.<rule>.<variant>`; the client formats the numbers in `params`.
  Every insight is shown as an indicator, never medical advice.
  """

  alias MilosTraining.Insights.Domain.Sufficiency

  @type inputs :: %{
          today: Date.t(),
          from: Date.t(),
          sessions: [map()],
          pr_days: [Date.t()],
          days: [map()],
          cravings: [map()],
          sleep_goal_minutes: pos_integer()
        }

  @type result :: %{
          status: :finding | :no_finding | :insufficient,
          weeks: non_neg_integer(),
          variant: String.t() | nil,
          params: map(),
          key: String.t() | nil,
          sample: map()
        }

  @callback id() :: String.t()
  @callback section() :: String.t() | nil
  @callback item() :: String.t() | nil
  @callback minimum() :: map()
  @callback compute(inputs()) :: result()

  @doc "A clear pattern. `key` is the qualitative part of the finding (never numbers)."
  def finding(weeks, variant, params, key) when is_binary(variant) and is_map(params) do
    %{
      status: :finding,
      weeks: weeks,
      variant: variant,
      params: params,
      key: Enum.join([variant | List.wrap(key)], ":"),
      sample: %{}
    }
  end

  def no_finding(weeks, sample \\ %{}),
    do: %{status: :no_finding, weeks: weeks, variant: nil, params: %{}, key: nil, sample: sample}

  def insufficient(weeks, sample \\ %{}),
    do: %{
      status: :insufficient,
      weeks: weeks,
      variant: nil,
      params: %{},
      key: nil,
      sample: sample
    }

  @doc """
  The common gate: the data spans at least four weeks (`dates` are the days
  that count) and every `checks` entry is true; otherwise `insufficient`.
  """
  def gated(dates, today, checks, sample, fun) when is_function(fun, 1) do
    weeks = Sufficiency.weeks(dates, today)

    if Sufficiency.enough_span?(dates, today) and Enum.all?(checks),
      do: fun.(weeks),
      else: insufficient(weeks, sample)
  end

  @doc "A ratio with one decimal."
  def ratio(a, b) when b > 0, do: Float.round(a / b, 1)

  @doc "Hours from minutes, to the half hour (7, 7.5)."
  def hours(minutes) when is_integer(minutes), do: Float.round(minutes / 30) / 2
end
