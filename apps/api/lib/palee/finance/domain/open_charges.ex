defmodule Palee.Finance.Domain.OpenCharges do
  @moduledoc """
  ADR-274: where a person's oldest unpaid charge stands, for «Οφειλές».

    * `"upcoming"`: it falls due later;
    * `"unpaid"`: it fell due and the box's grace days still keep access;
    * `"overdue"`: the grace days are over (access is blocked, ADR-017).
  """

  def state(nil, _grace_days, _today), do: "upcoming"

  def state(%Date{} = due_on, grace_days, %Date{} = today) do
    cond do
      Date.compare(due_on, today) == :gt -> "upcoming"
      Date.diff(today, due_on) > max(grace_days || 0, 0) -> "overdue"
      true -> "unpaid"
    end
  end
end
