defmodule Palee.TestSupport.BoxScreenFixtures do
  @moduledoc """
  Box screen tests (ADR-253) run on the box's own clock: these put the box in
  a zone where it is around midday right now, so "today" never splits at a
  midnight while a test runs.
  """

  alias Palee.Repo

  @doc "A fixed-offset zone where `now` is between 12:00 and 13:00."
  def midday_zone(%DateTime{} = now) do
    offset = 12 - now.hour

    cond do
      offset == 0 -> "Etc/GMT"
      offset > 0 -> "Etc/GMT-#{offset}"
      true -> "Etc/GMT+#{-offset}"
    end
  end

  @doc "Confirms `zone` as the box's time zone."
  def set_gym_zone!(organization_id, zone) do
    id = Ecto.UUID.dump!(organization_id)

    %{num_rows: updated} =
      Repo.query!(
        "UPDATE organization_settings SET timezone = $1, timezone_source = 'confirmed' WHERE organization_id = $2",
        [zone, id]
      )

    if updated == 0 do
      Repo.query!(
        """
        INSERT INTO organization_settings (id, organization_id, timezone, timezone_source, inserted_at, updated_at)
        VALUES ($1, $2, $3, 'confirmed', now(), now())
        """,
        [Ecto.UUID.dump!(Ecto.UUID.generate()), id, zone]
      )
    end

    :ok
  end
end
