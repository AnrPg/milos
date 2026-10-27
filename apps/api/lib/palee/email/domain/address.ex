defmodule Palee.Email.Domain.Address do
  @moduledoc """
  The recipient address rules of the outbox (ADR-203). An address is
  normalised the way invitations normalise it (`InvitationEmail`), so the
  suppression list, the throttles and the invitations agree on one
  spelling, and its digest is `InvitationEmail.digest/1`.
  """

  alias Palee.Organizations.Domain.InvitationEmail

  @max_length 254
  @shape ~r/\A[^\s@<>()\[\],;:"\\]+@[^\s@<>()\[\],;:"\\]+\.[^\s@<>()\[\],;:"\\]+\z/u

  @doc """
  `{:ok, normalized}` for a deliverable-looking address, else
  `{:error, :invalid_address}`. Control characters (a header injection)
  and display-name forms are refused; one `local@domain.tld` only.
  """
  def normalize(address) when is_binary(address) do
    normalized = InvitationEmail.normalize(address)

    if byte_size(normalized) <= @max_length and Regex.match?(@shape, normalized) and
         String.printable?(normalized),
       do: {:ok, normalized},
       else: {:error, :invalid_address}
  end

  def normalize(_address), do: {:error, :invalid_address}

  @doc "Whether `normalize/1` accepts the address."
  def valid?(address), do: match?({:ok, _normalized}, normalize(address))

  @doc "The SHA-256 digest the suppression list keys on (nil for a blank address)."
  defdelegate digest(address), to: InvitationEmail
end
