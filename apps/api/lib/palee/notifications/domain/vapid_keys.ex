defmodule Palee.Notifications.Domain.VapidKeys do
  @moduledoc """
  The Web Push (VAPID, RFC 8292) key pair the server signs every push with
  (ADR-277): a P-256 key, the public half as the 65-byte uncompressed point
  and the private half as the 32-byte scalar, both base64url without padding,
  the form browsers (`applicationServerKey`) and `web_push_elixir` expect.
  """

  @type t :: %{public_key: String.t(), private_key: String.t()}

  @spec generate() :: t()
  def generate do
    {public, private} = :crypto.generate_key(:ecdh, :prime256v1)
    %{public_key: encode(public), private_key: encode(private)}
  end

  @doc "True when both halves decode to a P-256 key of the right size."
  @spec valid?(map()) :: boolean()
  def valid?(%{public_key: public, private_key: private})
      when is_binary(public) and is_binary(private) do
    with {:ok, <<4, _point::binary-64>>} <- decode(public),
         {:ok, <<_scalar::binary-32>>} <- decode(private) do
      true
    else
      _ -> false
    end
  end

  def valid?(_keys), do: false

  defp encode(bytes), do: Base.url_encode64(bytes, padding: false)
  defp decode(text), do: Base.url_decode64(text, padding: false)
end
