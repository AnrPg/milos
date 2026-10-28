defmodule Palee.Organizations.Domain.JoinLinkPolicy do
  @moduledoc """
  Rules for the organization's public join links (ADR-216).

  A join link is an opt-in, organization-wide alternative to one-time
  invitations: while enabled, anyone holding the link can create an account
  (or use an existing one) and becomes a client with the link's role. There is
  one link per client role and the owner turns each on or off on its own, so
  a box can take in box members and athletes at the same time:

    * `member`, `/join/<slug>`: the box address. It stays guessable on purpose,
      because members also join by typing the box's link in «Τα box μου».
    * `athlete`, `/join/<slug>/athlete/<key>`: carries a random key, so a
      person holding the member link cannot turn it into the athlete link.
      The owner can replace the key, which retires every copy of the old link.

  The visitor never picks the role. Links only ever grant client roles; staff
  still need a one-time invitation. Stored under
  `organization_settings.settings["join_link"]`.
  """

  @settings_key "join_link"
  @client_roles ~w(member athlete)
  @keyed_roles ~w(athlete)

  def settings_key, do: @settings_key
  def client_roles, do: @client_roles

  @doc "Whether the role's link carries a secret key in its address."
  def keyed?(role), do: role in @keyed_roles

  @doc "A fresh, unguessable link key (72 random bits, URL-safe)."
  def new_key, do: 9 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  @doc """
  Reads both links from an organization settings map, with defaults. The
  earlier single link (`%{"enabled", "role"}`) had no key, so it can only
  carry over as the member link; an earlier athlete link reads as off until
  the owner turns it on again, which gives it a key.
  """
  def from_settings(settings) when is_map(settings) do
    case Map.get(settings, @settings_key) do
      %{"role" => legacy_role} = stored when is_binary(legacy_role) ->
        Map.new(@client_roles, fn role ->
          enabled = role == legacy_role and not keyed?(role) and stored["enabled"] == true
          {role, link(role, %{"enabled" => enabled})}
        end)

      %{} = stored ->
        Map.new(@client_roles, fn role -> {role, link(role, Map.get(stored, role))} end)

      _missing ->
        default()
    end
  end

  def from_settings(_settings), do: default()

  defp default, do: Map.new(@client_roles, fn role -> {role, link(role, nil)} end)

  defp link(role, stored) do
    stored = if is_map(stored), do: stored, else: %{}
    base = %{"enabled" => Map.get(stored, "enabled") == true}

    if keyed?(role) do
      key = Map.get(stored, "key")
      Map.put(base, "key", if(is_binary(key) and key != "", do: key))
    else
      base
    end
  end

  @doc """
  Validates an admin change to one link and merges it over the current links.
  `params` names the `role` and may set `enabled` and, for a keyed link,
  `rotate_key: true`. A keyed link gets `fresh_key` when it is first turned on
  or when its key is rotated.
  """
  def update(current, params, fresh_key)
      when is_map(current) and is_map(params) and is_binary(fresh_key) do
    role = value(params, :role, nil)
    existing = role in @client_roles && Map.get(current, role, link(role, nil))

    with true <- is_map(existing) || {:error, :invalid_join_link},
         enabled = value(params, :enabled, existing["enabled"]),
         rotate = value(params, :rotate_key, false),
         true <- (is_boolean(enabled) and is_boolean(rotate)) || {:error, :invalid_join_link},
         true <- (not rotate or keyed?(role)) || {:error, :invalid_join_link} do
      {:ok, Map.put(current, role, apply_change(role, existing, enabled, rotate, fresh_key))}
    end
  end

  def update(_current, _params, _fresh_key), do: {:error, :invalid_join_link}

  defp apply_change(role, existing, enabled, rotate, fresh_key) do
    changed = Map.put(existing, "enabled", enabled)

    cond do
      not keyed?(role) -> changed
      rotate or (enabled and is_nil(existing["key"])) -> Map.put(changed, "key", fresh_key)
      true -> changed
    end
  end

  @doc """
  Whether a visitor can join through the `role` link, presenting `key` (`nil`
  for the member link), while the organization has `organization_status`.
  """
  def joinable?(join_links, role, key, organization_status) do
    link = role in @client_roles && Map.get(join_links, role)

    organization_status == :active and is_map(link) and link["enabled"] == true and
      key_matches?(role, link, key)
  end

  defp key_matches?(role, link, key) do
    if keyed?(role) do
      is_binary(key) and is_binary(link["key"]) and byte_size(key) == byte_size(link["key"]) and
        :crypto.hash_equals(key, link["key"])
    else
      is_nil(key)
    end
  end

  @doc """
  Decides what joining means for an account that may already belong to the
  organization. An active membership is left untouched (joining is
  idempotent, and a link never changes an existing role); a suspended or
  removed one is never reactivated by a public link.
  """
  def join_decision(nil), do: :create
  def join_decision(%{status: :active}), do: :already_member
  def join_decision(_membership), do: {:error, :membership_unavailable}

  defp value(params, key, default) do
    case Map.fetch(params, key) do
      {:ok, value} -> value
      :error -> Map.get(params, Atom.to_string(key), default)
    end
  end
end
