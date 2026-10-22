defmodule Palee.Infrastructure.Tenancy.RepoContext do
  alias Palee.Repo

  def run(%{organization_id: organization_id} = context, fun)
      when is_binary(organization_id) and is_function(fun, 0) do
    with_settings([{"app.organization_id", organization_id} | contextual_settings(context)], fun)
  end

  def run(%{user_id: user_id} = context, fun) when is_binary(user_id) and is_function(fun, 0) do
    with_settings(contextual_settings(context), fun)
  end

  def run(%{execution_authorization_check: true} = context, fun)
      when is_function(fun, 0) do
    with_settings(contextual_settings(context), fun)
  end

  # Invitation redemption is the one flow where the acting account is
  # legitimately not yet a member of the organization it is reading, so the
  # membership-based policies on the root tenant tables cannot apply. Narrow,
  # explicit, and set only by RedeemInvitation/InspectInvitation.
  def run(%{invitation_redemption: true} = context, fun) when is_function(fun, 0) do
    with_settings(contextual_settings(context), fun)
  end

  # ADR-122: the unauthenticated retired-slug lookup behind the web proxy's
  # 308 redirect. Its policies are SELECT-only and only ever answer which
  # canonical slug replaced a retired one. Set only by ResolveSlugAlias.
  def run(%{slug_alias_lookup: true} = context, fun) when is_function(fun, 0) do
    with_settings(contextual_settings(context), fun)
  end

  def run(_context, _fun), do: {:error, :missing_ownership_scope}

  # The settings this process holds on its checked-out connection while inside
  # `run/2`, so reads and nested runs need no round trip to the database.
  @active_settings {__MODULE__, :active_settings}

  def current_setting(name)
      when name in [
             "app.organization_id",
             "app.user_id",
             "app.admin_mode",
             "app.execution_authorization_check",
             "app.invitation_redemption",
             "app.slug_alias_lookup"
           ] do
    case Process.get(@active_settings) do
      %{^name => value} ->
        blank_to_nil(value)

      _unknown ->
        case Ecto.Adapters.SQL.query(Repo, "SELECT current_setting($1, true)", [name]) do
          {:ok, %{rows: [[value]]}} -> blank_to_nil(value)
          _error -> nil
        end
    end
  end

  defp with_settings(settings, fun) do
    runner =
      if Repo.in_transaction?() do
        fn callback -> callback.() end
      else
        &Repo.checkout/1
      end

    # Every store call runs through here, so the settings are read, set and
    # restored in one round trip each, not one per setting. Inside a run the
    # values are also kept in the process, so nested runs and
    # `current_setting/1` read them without a query, and a setting that
    # already holds the wanted value is neither set nor restored.
    runner.(fn ->
      active = Process.get(@active_settings)
      previous = previous_settings(settings, active)
      changed = Enum.reject(settings, fn setting -> setting in previous end)
      set_sessions(changed)
      Process.put(@active_settings, Map.merge(active || %{}, Map.new(settings)))

      try do
        fun.()
      after
        if active,
          do: Process.put(@active_settings, active),
          else: Process.delete(@active_settings)

        changed
        |> Enum.map(fn {name, _value} -> {name, previous |> List.keyfind(name, 0) |> elem(1)} end)
        |> set_sessions()
      end
    end)
  end

  # Outside any run the connection is read once, since callers (and tests) may
  # have set a value directly; inside a run the process already knows them.
  defp previous_settings(settings, active) do
    names = Enum.map(settings, &elem(&1, 0))

    values =
      if active && Enum.all?(names, &Map.has_key?(active, &1)) do
        Enum.map(names, &Map.fetch!(active, &1))
      else
        read_settings(names)
      end

    Enum.zip(names, values)
  end

  defp read_settings(names) do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT current_setting(name, true) FROM unnest($1::text[]) WITH ORDINALITY AS s(name, position) ORDER BY position",
        [names]
      )

    Enum.map(rows, fn [value] -> value || "" end)
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp set_sessions([]), do: :ok

  defp set_sessions(settings) do
    {names, values} = Enum.unzip(settings)

    Ecto.Adapters.SQL.query!(
      Repo,
      "SELECT set_config(name, value, false) FROM unnest($1::text[], $2::text[]) AS s(name, value)",
      [names, values]
    )

    :ok
  end

  defp contextual_settings(context) do
    []
    |> maybe_put_user(context)
    |> maybe_put_admin_mode(context)
    |> maybe_put_execution_authorization_check(context)
    |> maybe_put_invitation_redemption(context)
    |> maybe_put_slug_alias_lookup(context)
  end

  defp maybe_put_user(settings, %{user_id: user_id}) when is_binary(user_id),
    do: [{"app.user_id", user_id} | settings]

  defp maybe_put_user(settings, _context), do: settings

  # `app.admin_mode` only ever *requests* the widened execution policy; the
  # policy itself independently requires an active owner/admin/coach membership
  # in the execution's own organization (F-23), so this flag cannot grant
  # anything on its own.
  #
  # Prefer the membership role of the organization being opened (F-29). Only
  # where no tenant context exists - the executions routes are user-scoped, not
  # org-scoped - does the account-wide role stand in, and there the policy's own
  # membership check remains the authority.
  @admin_mode_roles [:owner, :admin, :coach]

  defp maybe_put_admin_mode(settings, %{role: role}) when role in @admin_mode_roles,
    do: [{"app.admin_mode", "true"} | settings]

  defp maybe_put_admin_mode(settings, %{role: _role}), do: settings

  defp maybe_put_admin_mode(settings, %{account: %{role: role}}) do
    if to_string(role) == "admin" do
      [{"app.admin_mode", "true"} | settings]
    else
      settings
    end
  end

  defp maybe_put_admin_mode(settings, _context), do: settings

  defp maybe_put_execution_authorization_check(settings, %{execution_authorization_check: true}),
    do: [{"app.execution_authorization_check", "true"} | settings]

  defp maybe_put_execution_authorization_check(settings, _context), do: settings

  defp maybe_put_invitation_redemption(settings, %{invitation_redemption: true}),
    do: [{"app.invitation_redemption", "true"} | settings]

  defp maybe_put_invitation_redemption(settings, _context), do: settings

  defp maybe_put_slug_alias_lookup(settings, %{slug_alias_lookup: true}),
    do: [{"app.slug_alias_lookup", "true"} | settings]

  defp maybe_put_slug_alias_lookup(settings, _context), do: settings
end
