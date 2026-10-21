defmodule Palee.Application.SeasonSweep do
  @moduledoc """
  The daily season sweep (ADR-167) over every active gym: a published season
  whose start date came is marked running; one past its last day completes
  and its #season channel is archived. Reads already derive both from the
  dates, so a late sweep never shows a wrong status.
  """

  require Logger

  alias Palee.Application.Seasons
  alias Palee.Organizations

  def call do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} ->
      try do
        Seasons.sweep(%{organization_id: organization.id})
      rescue
        error ->
          Logger.error(
            "season_sweep_failed organization_id=#{organization.id} #{Exception.message(error)}"
          )
      end
    end)
  end
end
