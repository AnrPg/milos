defmodule Palee.Buddies.Domain.LinkPolicy do
  @moduledoc """
  The buddy link's life (ADR-160 §1, board 15 Q1, Q2, Q7). A member invites
  up to two people; nothing starts until the other accepts. An invite
  expires after seven days. Either side can stop at any time, quietly (the
  other sees it on their page, no push); a block ends it at once.

      pending ──accept──▶ active ──leave/block──▶ ended
         │ ├─decline──▶ declined
         │ ├─cancel/block──▶ ended
         │ └─(7 days)──▶ expired

  `role` is the actor's side of the link: `:requester` (who asked for
  support) or `:buddy` (who gives it).
  """

  @statuses ~w(pending active declined ended expired)
  @open ~w(pending active)
  @max_buddies 2
  @invite_days 7

  def statuses, do: @statuses
  def open_statuses, do: @open
  def max_buddies, do: @max_buddies
  def invite_days, do: @invite_days

  @doc "When an invite sent at `now` stops working."
  def expires_at(%DateTime{} = now), do: DateTime.add(now, @invite_days * 86_400, :second)

  @doc "The status as it stands at `now`: a pending invite past its date is expired."
  def effective_status(%{status: "pending", expires_at: %DateTime{} = at}, %DateTime{} = now) do
    if DateTime.compare(at, now) == :gt, do: "pending", else: "expired"
  end

  def effective_status(%{status: status}, _now), do: status

  def open?(link, now), do: effective_status(link, now) in @open

  @doc "The actor's side of `link`, or nil when they are not on it."
  def role(%{user_id: user_id}, user_id), do: :requester
  def role(%{buddy_user_id: user_id}, user_id) when is_binary(user_id), do: :buddy
  def role(_link, _user_id), do: nil

  @doc "The other person on the link, as seen by `user_id`."
  def other(%{user_id: user_id, buddy_user_id: buddy}, user_id), do: buddy
  def other(%{user_id: requester}, _user_id), do: requester

  @doc """
  Whether a new invite fits: at most #{@max_buddies} open (pending or
  active) invites of one's own, counted at `now`.
  """
  def check_limit(links, now) do
    if Enum.count(links, &open?(&1, now)) < @max_buddies,
      do: :ok,
      else: {:error, :buddy_limit_reached}
  end

  @doc """
  The change `action` makes to `link` when `role` does it at `now`, or why
  it cannot happen. Returns the fields to write.
  """
  def transition(link, action, role, %DateTime{} = now) do
    do_transition(effective_status(link, now), action, role, link, now)
  end

  defp do_transition("pending", :accept, :buddy, _link, now),
    do: {:ok, %{status: "active", started_at: now, expires_at: nil}}

  defp do_transition("pending", :decline, :buddy, _link, now),
    do: {:ok, %{status: "declined", ended_at: now}}

  defp do_transition("pending", action, role, link, now)
       when action in [:leave, :block] and not is_nil(role),
       do: {:ok, ended(link, role, now)}

  defp do_transition("active", action, role, link, now)
       when action in [:leave, :block] and not is_nil(role),
       do: {:ok, ended(link, role, now)}

  defp do_transition("expired", _action, _role, _link, _now), do: {:error, :buddy_invite_expired}

  defp do_transition(status, _action, _role, _link, _now) when status in ~w(declined ended),
    do: {:error, :buddy_link_closed}

  defp do_transition(_status, _action, nil, _link, _now), do: {:error, :not_found}
  defp do_transition(_status, _action, _role, _link, _now), do: {:error, :forbidden}

  defp ended(link, role, now) do
    by = if role == :requester, do: link.user_id, else: link.buddy_user_id
    %{status: "ended", ended_at: now, ended_by_id: by, expires_at: nil}
  end

  @doc "Whether the other person hears about `action` (only invites and acceptances)."
  def notifies?(:invite), do: true
  def notifies?(:accept), do: true
  def notifies?(_action), do: false

  @doc "Only the person who asks for support chooses what their buddy receives."
  def can_set_summary?(link, user_id, now),
    do: role(link, user_id) == :requester and open?(link, now)
end
