defmodule Palee.Application.CompleteProductTour do
  @moduledoc "Records that the account finished a product tour (admin, member or athlete)."

  alias Palee.Identity

  def call(%{id: user_id}, audience), do: Identity.mark_tour_completed(user_id, audience)
end
