defmodule Palee.FakeMapLinkResolver do
  @moduledoc "Test stand-in: one known short link expands to a long one."

  @behaviour Palee.Application.Ports.MapLinkResolver

  @impl true
  def expand("https://maps.app.goo.gl/kypseli"),
    do:
      {:ok,
       "https://www.google.com/maps/place/Box/@38.0,23.73,17z/data=!3d38.000563!4d23.7345526"}

  def expand(_url), do: {:error, :map_link_unresolved}
end
