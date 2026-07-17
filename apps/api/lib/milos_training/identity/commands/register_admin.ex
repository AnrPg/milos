defmodule MilosTraining.Identity.Commands.RegisterAdmin do
  alias MilosTraining.Identity.UserStore

  def call(params), do: UserStore.create_admin_user(params)
end
