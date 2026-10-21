defmodule Palee.Infrastructure.Auth.PasswordHasher do
  def hash(password), do: Palee.Infrastructure.Auth.Password.hash(password)
end
