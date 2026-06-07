defmodule MilosTraining.Identity.PasswordHasher do
  def hash(password), do: impl().hash(password)

  defp impl do
    Application.get_env(
      :milos_training,
      :identity_password_hasher,
      MilosTraining.Infrastructure.Auth.PasswordHasher
    )
  end
end
