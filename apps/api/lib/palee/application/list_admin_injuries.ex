defmodule Palee.Application.ListAdminInjuries do
  alias Palee.Wellbeing

  def call(context, params),
    do:
      Palee.Wellbeing.WellbeingStore.with_context(context, fn ->
        call(params)
      end)

  def call(params), do: {:ok, %{injuries: Wellbeing.list_injuries(params)}}
end
