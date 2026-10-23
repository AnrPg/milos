defmodule Palee.Identity.Domain.PasswordResetPolicy do
  @moduledoc """
  ADR-187: the rules of a password reset request. Pure.

  A request is handled by one person at a time: the first handler to open
  it claims it. A claim left idle for 30 minutes lapses, and the vendor
  can always take a request over. An issued reset link works once, for 24
  hours; after that the request shows as expired until a handler sends a
  new link or dismisses it.
  """

  @claim_idle_minutes 30
  @link_ttl_hours 24

  def claim_idle_minutes, do: @claim_idle_minutes
  def link_ttl_hours, do: @link_ttl_hours

  def link_expires_at(now), do: DateTime.add(now, @link_ttl_hours * 3600, :second)

  @doc "Whether the request's link was issued and has lapsed."
  def expired?(%{status: "link_issued", link_expires_at: %DateTime{} = expires_at}, now),
    do: DateTime.compare(expires_at, now) != :gt

  def expired?(_request, _now), do: false

  @doc "Whether a claim still holds (someone opened it within the idle window)."
  def claim_active?(%{claimed_by_user_id: nil}, _now), do: false
  def claim_active?(%{claimed_at: nil}, _now), do: false

  def claim_active?(%{claimed_at: claimed_at}, now),
    do: DateTime.diff(now, claimed_at, :second) < @claim_idle_minutes * 60

  @doc """
  The state a viewer sees: `:open`, `:mine` (they hold the claim),
  `:taken` (someone else holds it), `:link_sent` or `:expired`.
  """
  def state(request, viewer_id, now) do
    cond do
      expired?(request, now) -> :expired
      request.status == "link_issued" -> :link_sent
      claim_active?(request, now) and request.claimed_by_user_id == viewer_id -> :mine
      claim_active?(request, now) -> :taken
      true -> :open
    end
  end

  @doc """
  Whether `viewer_id` may claim the request now. The vendor may take over a
  request someone else holds; nobody claims a request whose link is out and
  still valid, except the person who sent it.
  """
  def can_claim?(request, viewer_id, sources, now) do
    case state(request, viewer_id, now) do
      state when state in [:open, :mine, :expired] -> true
      :taken -> "vendor" in sources
      :link_sent -> request.claimed_by_user_id == viewer_id or "vendor" in sources
    end
  end

  @doc "Only the claim holder acts on a request (issue a link, reject, dismiss)."
  def holds_claim?(request, viewer_id, now),
    do:
      request.claimed_by_user_id == viewer_id and
        (claim_active?(request, now) or expired?(request, now) or request.status == "link_issued")

  @doc "A url-safe one-time token and the hash stored in its place."
  def new_token do
    token = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    {token, hash_token(token)}
  end

  def hash_token(token) when is_binary(token), do: :crypto.hash(:sha256, token)
end
