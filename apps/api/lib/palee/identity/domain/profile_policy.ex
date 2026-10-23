defmodule Palee.Identity.Domain.ProfilePolicy do
  @moduledoc """
  ADR-187: one login (one email, one password) holds up to three profiles.
  Each profile is a full account with its own @handle, display name, role,
  memberships and sessions. Handle changes are rate-limited and an old handle
  stays reserved for its former owner for a while, so links and @mentions are
  not hijacked right after a rename. Pure.
  """

  @max_profiles 3
  @handle_change_cooldown_days 14
  @handle_reservation_days 30

  def max_profiles, do: @max_profiles
  def handle_change_cooldown_days, do: @handle_change_cooldown_days
  def handle_reservation_days, do: @handle_reservation_days

  def can_add_profile?(existing_count) when is_integer(existing_count),
    do: existing_count < @max_profiles

  @doc "When the next handle change is allowed, or :now."
  def next_handle_change(nil, _now), do: :now

  def next_handle_change(%DateTime{} = changed_at, %DateTime{} = now) do
    allowed_at = DateTime.add(changed_at, @handle_change_cooldown_days * 86_400, :second)
    if DateTime.compare(allowed_at, now) == :gt, do: allowed_at, else: :now
  end

  def reservation_ends_at(%DateTime{} = released_at),
    do: DateTime.add(released_at, @handle_reservation_days * 86_400, :second)
end
