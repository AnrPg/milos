defmodule MilosTraining.Application.PasswordVerifier do
  def verify(password, password_hash), do: impl().verify(password, password_hash)
  def no_user_verify, do: impl().no_user_verify()

  defp impl do
    Application.fetch_env!(:milos_training, :password_verifier)
  end
end
