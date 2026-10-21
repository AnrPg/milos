defmodule Palee.Application.EventInvites do
  @moduledoc """
  Guest pass links (ADR-153, board 8): a going member shares a link; a
  friend who signs in with it takes a place as that member's guest. The
  link is a signed, stateless token naming the event, its box and the
  member; nothing is stored until the friend says «Θα έρθω». Whether it
  still works (guest passes on, the member still going, places left for
  their guests, the event ahead) is decided when it is used, so a link
  never outlives the rules. It expires #{60} days after it was made.
  """

  alias Palee.Application.SignedToken

  @salt "community-event-invite-v1"
  @max_age_days 60

  def sign(%{id: event_id, organization_id: organization_id}, inviter_id) do
    SignedToken.sign(@salt, %{"e" => event_id, "o" => organization_id, "i" => inviter_id})
  end

  @doc "`{:ok, %{event_id, organization_id, inviter_id}}` or `{:error, :invalid_invite}`."
  def verify(token) when is_binary(token) and token != "" do
    case SignedToken.verify(@salt, token, max_age: @max_age_days * 86_400) do
      {:ok, %{"e" => event_id, "o" => organization_id, "i" => inviter_id}} ->
        {:ok, %{event_id: event_id, organization_id: organization_id, inviter_id: inviter_id}}

      _invalid ->
        {:error, :invalid_invite}
    end
  end

  def verify(_token), do: {:error, :invalid_invite}

  @doc "The path in the member app that opens the event with the invitation."
  def path(event_id, token), do: "/events/#{event_id}?invite=#{URI.encode_www_form(token)}"
end
