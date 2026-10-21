defmodule Palee.Wellbeing.Queries.ListInjuriesForUser do
  alias Palee.Wellbeing.WellbeingStore

  def call(user_id), do: WellbeingStore.list_injuries_for_user(user_id)
end
