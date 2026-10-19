defmodule MilosTraining.Application.SavedFilters do
  @moduledoc """
  ADR-151: a person's filter choices per list surface. The last-used filter
  is remembered automatically; named combinations are saved on request (at
  most 20 per surface; saving an existing name replaces it).
  """

  alias MilosTraining.Identity

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
         {:ok, _filter} <-
           Identity.put_last_used_filter(context, surface, params, DateTime.utc_now()) do
      get(context, surface)
    end
  end

  def save(context, surface, name, params) do
    with :ok <- Identity.validate_filter_surface(surface),
         :ok <- Identity.validate_filter_params(params),
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
