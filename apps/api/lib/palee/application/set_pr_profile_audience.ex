defmodule Palee.Application.SetPRProfileAudience do
  @moduledoc """
  `PUT /api/prs/:id/profile-audience` (ADR-196): the owner puts one PR on
  their profile for followers, or takes it back to private. Coaches' access
  (the ADR-139 ladder) and explicit grants (ADR-129) are not touched.
  """

  alias Palee.Pantheon

  def call(%{user_id: user_id} = context, id, audience) do
    with :ok <- Pantheon.validate_profile_audience(audience) do
      Pantheon.with_user_context(context, fn ->
        Pantheon.set_profile_audience(id, user_id, audience)
      end)
    end
  end
end
