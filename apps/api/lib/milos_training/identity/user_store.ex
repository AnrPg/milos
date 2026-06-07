defmodule MilosTraining.Identity.UserStore do
  @behaviour MilosTraining.Identity.Ports.UserStore

  def create_user(params), do: impl().create_user(params)
  def delete_user(user), do: impl().delete_user(user)
  def update_user_role(user, role), do: impl().update_user_role(user, role)
  def get_by_nickname(nickname), do: impl().get_by_nickname(nickname)
  def get_by_id(id), do: impl().get_by_id(id)

  defp impl do
    Application.get_env(
      :milos_training,
      :identity_user_store,
      MilosTraining.Infrastructure.Identity.EctoUserStore
    )
  end
end
