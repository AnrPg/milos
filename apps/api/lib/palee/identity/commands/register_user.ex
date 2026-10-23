defmodule Palee.Identity.Commands.RegisterUser do
  @moduledoc "A new login (new email) with its first profile (ADR-187)."
  alias Palee.Identity.UserStore

  def call(params), do: UserStore.create_login_with_profile(params)
end
