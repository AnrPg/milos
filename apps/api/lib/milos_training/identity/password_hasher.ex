defmodule MilosTraining.Identity.PasswordHasher do
  def hash(password), do: impl().hash(password)

  defp impl do
    Application.fetch_env!(:milos_training, :identity_password_hasher)
  end
end
