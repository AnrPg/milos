defmodule Palee.Identity.Domain.ProductTours do
  @moduledoc "Product tour audiences an account can complete (ADR-107)."

  @audiences ~w(admin member athlete)

  def audiences, do: @audiences

  def complete(completed, audience) when audience in @audiences,
    do: {:ok, Enum.uniq((completed || []) ++ [audience])}

  def complete(_completed, _audience), do: {:error, :invalid_tour}
end
