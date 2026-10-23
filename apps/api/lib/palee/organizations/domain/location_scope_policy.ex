defmodule Palee.Organizations.Domain.LocationScopePolicy do
  @moduledoc """
  Which branches (`facility_locations`) a staff member works at (ADR-186).

  A scope is `:all` («Όλα τα καταστήματα») or a sorted list of location ids.
  It is a property of the membership and narrows every staff role the
  membership holds; it never touches what a member or athlete may do as a
  client, because their packages already say which branches they cover.

  Rules:

    * owners always work everywhere, and so does a membership without a staff
      role;
    * a located thing (class, booking, check-in, door, appointment slot,
      event, cleaning area, machine) is in scope when its location is in the
      scope;
    * a thing without a location belongs to the whole business: only staff
      with `:all` act on it, unless an area decides otherwise (ADR-186 lists
      them);
    * capabilities over the business as a whole (`organization_wide/0`) are
      dropped for branch-scoped staff;
    * nobody grants a scope wider than their own, nor manages the roles of
      staff working outside it.

  Pure: no Repo, no clock.
  """

  alias Palee.Organizations.Domain.MembershipPolicy

  @type scope :: :all | [String.t()]

  @max_locations 200

  # Capabilities whose objects have no branch: gym-wide settings and branding,
  # the package catalogue and promotions, finance settings and reports,
  # business analytics, clubs and their settings, and the owner's own powers.
  @organization_wide [
    :manage_settings,
    :manage_packages,
    :manage_promotions,
    :manage_finance_settings,
    :view_finance_reports,
    :view_business_analytics,
    :manage_community,
    :create_organization,
    :manage_organization_lifecycle,
    :manage_platform_subscription,
    :grant_admin_roles
  ]

  @doc "Capabilities a branch-scoped membership never holds."
  def organization_wide, do: @organization_wide

  @doc "Most branches one membership or invitation may list."
  def max_locations, do: @max_locations

  @doc """
  The effective scope of a membership with `roles`, its `all_locations` flag
  and the ids of its active (not archived) scoped locations.
  """
  def effective(roles, all_locations?, location_ids) do
    roles = List.wrap(roles)

    cond do
      :owner in roles -> :all
      not staff?(roles) -> :all
      all_locations? != false -> :all
      true -> location_ids |> List.wrap() |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()
    end
  end

  @doc "Whether a role set holds any staff role (owner and admin included)."
  def staff?(roles), do: Enum.any?(List.wrap(roles), &(&1 not in MembershipPolicy.client_roles()))

  @doc "The scope a tenant context carries; contexts built without one work everywhere."
  def scope(%{location_scope: scope}) when is_list(scope), do: scope
  def scope(_context), do: :all

  def all?(scope_or_context), do: to_scope(scope_or_context) == :all

  @doc "Whether a location id (nil = no location) is in scope."
  def covers?(scope_or_context, location_id) do
    case to_scope(scope_or_context) do
      :all -> true
      _scoped when location_id in [nil, ""] -> false
      ids -> location_id in ids
    end
  end

  @doc "`:ok`, or `{:error, :location_out_of_scope}`."
  def authorize(scope_or_context, location_id) do
    if covers?(scope_or_context, location_id), do: :ok, else: {:error, :location_out_of_scope}
  end

  @doc """
  Keeps the items in scope. `location_of` reads an item's location id; by
  default its `:location_id` field or key.
  """
  def filter(scope_or_context, items, location_of \\ &location_id/1) do
    case to_scope(scope_or_context) do
      :all -> items
      ids -> Enum.filter(items, &(location_of.(&1) in ids))
    end
  end

  @doc """
  Narrows a filter of location ids to the scope: `nil` (any location) becomes
  the scope itself, a requested id outside it becomes `[]` (nothing).
  """
  def restrict(scope_or_context, requested) do
    case {to_scope(scope_or_context), requested} do
      {:all, requested} -> requested
      {ids, nil} -> ids
      {ids, ""} -> ids
      {ids, requested} -> Enum.filter(List.wrap(requested), &(&1 in ids))
    end
  end

  @doc """
  The location a desk action happens at. A branch-scoped desk must name one
  of its branches, or works at its only branch when it has one.
  """
  def desk_location(scope_or_context, location_id) do
    case {to_scope(scope_or_context), location_id} do
      {:all, id} -> {:ok, blank_to_nil(id)}
      {[only], id} when id in [nil, ""] -> {:ok, only}
      {_ids, id} when id in [nil, ""] -> {:error, :location_required}
      {ids, id} -> if id in ids, do: {:ok, id}, else: {:error, :location_out_of_scope}
    end
  end

  @doc "Drops the organization-wide capabilities from a branch-scoped capability map."
  def narrow_capabilities(capabilities, :all), do: capabilities

  def narrow_capabilities(capabilities, scope) when is_list(scope),
    do: Map.drop(capabilities, @organization_wide)

  @doc """
  Whether a granter with `granter_scope` may give someone `target_scope`:
  a scope inside their own, never `:all` unless they hold `:all`.
  """
  def can_grant_scope?(:all, _target_scope), do: true
  def can_grant_scope?(_granter_scope, :all), do: false
  def can_grant_scope?(_granter_scope, []), do: false

  def can_grant_scope?(granter_scope, target_scope)
      when is_list(granter_scope) and is_list(target_scope),
      do: Enum.all?(target_scope, &(&1 in granter_scope))

  @doc """
  Whether a granter may change the roles or scope of someone holding
  `target_roles` with `target_scope`: staff must work inside the granter's
  scope; clients belong to the whole business.
  """
  def can_manage?(granter_scope, target_roles, target_scope) do
    if staff?(target_roles), do: can_grant_scope?(granter_scope, target_scope), else: true
  end

  @doc """
  The scope a granter's change results in, checked against their own:
  `:ok` or `{:error, :location_scope_exceeded}`.
  """
  def authorize_grant(granter_scope, target_scope) do
    if can_grant_scope?(granter_scope, target_scope),
      do: :ok,
      else: {:error, :location_scope_exceeded}
  end

  @doc """
  Parses a requested scope: `%{all_locations: true}` or `%{location_ids: [...]}`
  (string or atom keys). Ids must be among `known_ids` (the business's active
  locations). Returns `{:ok, scope}` or `{:error, :invalid_location_scope}`.
  """
  def parse(params, known_ids) when is_map(params) do
    all? = value(params, :all_locations)
    ids = value(params, :location_ids)

    cond do
      all? in [true, "true"] -> {:ok, :all}
      not is_list(ids) or ids == [] -> {:error, :invalid_location_scope}
      length(Enum.uniq(ids)) > @max_locations -> {:error, :invalid_location_scope}
      Enum.all?(ids, &(&1 in known_ids)) -> {:ok, ids |> Enum.uniq() |> Enum.sort()}
      true -> {:error, :invalid_location_scope}
    end
  end

  def parse(_params, _known_ids), do: {:error, :invalid_location_scope}

  @doc "Whether params carry a scope at all (so a caller can leave it unchanged)."
  def requested?(params) when is_map(params),
    do: not is_nil(value(params, :all_locations)) or not is_nil(value(params, :location_ids))

  def requested?(_params), do: false

  @doc """
  The scope a membership ends with when it redeems an invitation scoped to
  `invited`: a client-only membership takes the invitation's scope; staff keep
  what they had plus the invited branches.
  """
  def merge_on_redeem(current_roles, current_scope, invited) do
    cond do
      not staff?(current_roles) -> invited
      current_scope == :all or invited == :all -> :all
      true -> (current_scope ++ invited) |> Enum.uniq() |> Enum.sort()
    end
  end

  @doc "The JSON shape of a scope."
  def to_payload(:all), do: %{all_locations: true, location_ids: []}
  def to_payload(ids) when is_list(ids), do: %{all_locations: false, location_ids: ids}

  defp to_scope(:all), do: :all
  defp to_scope(ids) when is_list(ids), do: ids
  defp to_scope(context), do: scope(context)

  defp location_id(%{location_id: id}), do: id
  defp location_id(%{"location_id" => id}), do: id
  defp location_id(_item), do: nil

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp value(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
