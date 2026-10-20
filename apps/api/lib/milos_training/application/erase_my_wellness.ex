defmodule MilosTraining.Application.EraseMyWellness do
  @moduledoc """
  «Διαγραφή όλων» per section (ADR-147 D11, ADR-159 §4): `wellness` removes
  every water, sleep and meal entry and the targets; `cravings` removes every
  craving. Irreversible; the web asks for confirmation first.
  """

  alias MilosTraining.Application.{BroadcastUserSync, WellnessInput}
  alias MilosTraining.Wellness

  def call(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    with {:ok, sections} <- sections(WellnessInput.param(params, "sections")),
         {:ok, counts} <-
           Wellness.with_context(context, fn ->
             Wellness.transaction(fn -> Wellness.erase(user_id, sections, now) end)
           end) do
      BroadcastUserSync.for_user(user_id, ["my_wellbeing"], reason: "wellness_erased")
      {:ok, counts}
    end
  end

  defp sections(sections) when is_binary(sections),
    do: sections |> String.split(",", trim: true) |> sections()

  defp sections([_ | _] = sections) do
    sections = Enum.uniq(sections)

    if Enum.all?(sections, &(&1 in Wellness.erasable_sections())),
      do: {:ok, sections},
      else: {:error, :unknown_wellness_section}
  end

  defp sections(_sections), do: {:error, :unknown_wellness_section}
end
