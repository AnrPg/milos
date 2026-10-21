defmodule Palee.Identity.Commands.RegisterUser do
  alias Palee.Identity.UserStore

  def call(params), do: UserStore.create_user(params)
end
