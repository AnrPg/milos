defmodule Palee.Wellbeing.Commands.MarkHealed do
  alias Palee.Wellbeing.WellbeingStore

  def call(injury_report_id, actor_id, healed_on),
    do: WellbeingStore.mark_healed(injury_report_id, actor_id, healed_on)
end
