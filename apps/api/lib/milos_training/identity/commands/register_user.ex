defmodule MilosTraining.Identity.Commands.RegisterUser do
  alias MilosTraining.Identity.UserStore

  def call(params), do: UserStore.create_user(params)
end
