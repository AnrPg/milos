defmodule MilosTraining.Organizations.Domain.InvitationToken do
  @moduledoc false

  @entropy_bytes 32
  @maximum_encoded_bytes 256

  def generate do
    @entropy_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  def digest(token) when is_binary(token), do: :crypto.hash(:sha256, token)

  def decode(token)
      when is_binary(token) and byte_size(token) >= 20 and
             byte_size(token) <= @maximum_encoded_bytes,
      do: {:ok, digest(token)}

  def decode(_token), do: {:error, :invalid_invitation}
end
