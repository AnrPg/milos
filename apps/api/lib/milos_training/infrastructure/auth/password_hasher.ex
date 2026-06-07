defmodule MilosTraining.Infrastructure.Auth.PasswordHasher do
  def hash(password), do: MilosTraining.Infrastructure.Auth.Password.hash(password)
end
