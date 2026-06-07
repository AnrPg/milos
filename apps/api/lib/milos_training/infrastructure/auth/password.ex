defmodule MilosTraining.Infrastructure.Auth.Password do
  @behaviour MilosTraining.Application.Ports.PasswordVerifier

  def hash(password), do: Argon2.hash_pwd_salt(password)

  @impl true
  def verify(password, password_hash), do: Argon2.verify_pass(password, password_hash)

  @impl true
  def no_user_verify, do: Argon2.no_user_verify()
end
