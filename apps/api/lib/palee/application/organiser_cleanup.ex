defmodule Palee.Application.OrganiserCleanup do
  @moduledoc """
  ADR-185 §1 clean-up: a person's organiser organisation is created only
  after their first event validated, but the event can still fail after it
  (or be the only thing they ever tried). An organiser organisation that
  has had no event at all for a day is archived; «Ως εγώ» brings it back.
  One that once had events is kept like any dormant tenant (ADR-117).
  """

  alias Palee.{Community, Organizations}

  @grace_hours 24

  def call(now \\ DateTime.utc_now()) do
    before = DateTime.add(now, -@grace_hours, :hour)

    archived =
      %{}
      |> Community.empty_organiser_organization_ids(before)
      |> Enum.count(&match?({:ok, _}, Organizations.archive_empty_organiser(&1)))

    {:ok, %{archived: archived}}
  end
end
