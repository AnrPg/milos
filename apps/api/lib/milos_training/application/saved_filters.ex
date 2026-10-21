defmodule MilosTraining.Application.SavedFilters do
  @moduledoc """
  ADR-151: a person's filter choices per list surface. The last-used filter
  is remembered automatically; named combinations are saved on request (at
  most 20 per surface; saving an existing name replaces it).

  Γύρω μου (`around_me`, ADR-154) has a typed, versioned filter: its params
  are parsed and stored in their canonical form, and a named Γύρω μου
  filter can carry a daily alert.
  """

  alias MilosTraining.Application.AroundMe
  alias MilosTraining.{Analytics, Execution, Identity, Journal, Places}

  @around "around_me"

  def get(context, surface) do
    with :ok <- Identity.validate_filter_surface(surface) do
      filters = Identity.list_saved_filters(context, surface)
      last = Enum.find(filters, &(&1.kind == "last_used"))

      {:ok,
       %{
         surface: surface,
         last_used: last && last.params,
         saved: for(%{kind: "named"} = f <- filters, do: Map.delete(f, :kind))
       }}
    end
  end

  def remember(context, surface, params) do
    with :ok <- Identity.validate_filter_surface(surface),
         :ok <- Identity.validate_filter_params(params),
         {:ok, params} <- normalize(surface, params),
         {:ok, _filter} <-
           Identity.put_last_used_filter(context, surface, params, DateTime.utc_now()) do
      get(context, surface)
    end
  end

  def save(context, surface, name, params) do
    with :ok <- Identity.validate_filter_surface(surface),
         :ok <- Identity.validate_filter_params(params),
         {:ok, params} <- normalize(surface, params),
         {:ok, name} <- Identity.normalize_filter_name(name),
         :ok <- room_for(context, surface, name),
         {:ok, _filter} <-
           Identity.put_named_filter(context, surface, name, params, DateTime.utc_now()) do
      get(context, surface)
    end
  end

  def delete(context, surface, id) do
    with :ok <- Identity.validate_filter_surface(surface),
         :ok <- Identity.delete_named_filter(context, id) do
      get(context, surface)
    end
  end

  @doc """
  Turns a named Γύρω μου filter's daily alert on or off. Turning it on
  counts only what appears from now on.
  """
  def set_alert(context, surface, id, enabled, now \\ DateTime.utc_now())

  def set_alert(context, @around, id, enabled, now) when is_boolean(enabled) do
    with {:ok, _filter} <- Identity.set_filter_alert(context, id, enabled, now) do
      get(context, @around)
    end
  end

  def set_alert(_context, @around, _id, _enabled, _now),
    do: {:error, [enabled: "must be true or false"]}

  def set_alert(_context, surface, _id, _enabled, _now) do
    with :ok <- Identity.validate_filter_surface(surface),
         do: {:error, :filter_alerts_unsupported}
  end

  defp normalize(@around, params) do
    with {:ok, filter} <- Places.parse_filter(params, AroundMe.vocabulary()) do
      {:ok, Places.filter_params(filter)}
    end
  end

  # ADR-162: the journal, Vault and Πρόοδος filters are typed and versioned.
  defp normalize("journal", params) do
    with {:ok, filter} <- Journal.parse_filter(params), do: {:ok, Journal.filter_params(filter)}
  end

  defp normalize("vault", params) do
    with {:ok, filter} <- Execution.parse_vault_filter(params),
         do: {:ok, Execution.vault_filter_params(filter)}
  end

  defp normalize("progress", params) do
    with {:ok, filter} <- Analytics.parse_progress_filter(params),
         do: {:ok, Analytics.progress_filter_params(filter)}
  end

  defp normalize(_surface, params), do: {:ok, params}

  # Replacing an existing name never needs room.
  defp room_for(context, surface, name) do
    existing = Identity.list_saved_filters(context, surface)

    replacing? =
      Enum.any?(
        existing,
        &(&1.kind == "named" and String.downcase(&1.name) == String.downcase(name))
      )

    if replacing? or
         Identity.count_named_filters(context, surface) < Identity.max_named_filters(),
       do: :ok,
       else: {:error, :too_many_saved_filters}
  end
end
