defmodule Palee.Pantheon.Queries.GetStrengthTrend do
  @moduledoc """
  «Δύναμη» (ADR-285) for one person: their weight PRs and PR history through
  the store port, worked out by `Domain.StrengthTrend`. Runs in the caller's
  scope (the person's own rows under RLS, ADR-129).
  """

  alias Palee.Pantheon.Domain.StrengthTrend
  alias Palee.Pantheon.PRStore

  @spec call(binary(), Date.t()) :: StrengthTrend.t() | nil
  def call(user_id, %Date{} = today) do
    StrengthTrend.calculate(
      PRStore.list_user_prs(user_id),
      PRStore.list_user_pr_history(user_id),
      today
    )
  end
end
