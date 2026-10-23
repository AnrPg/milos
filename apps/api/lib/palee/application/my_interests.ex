defmodule Palee.Application.MyInterests do
  @moduledoc """
  «Τι κάνεις»: a person's disciplines and level (ADR-183), read and replaced
  whole. Disciplines are validated against the box vocabulary, so a key a
  box can offer is a key a person can pick.
  """

  alias Palee.{Interests, Organizations}

  def get(context), do: {:ok, present(Interests.get(context))}

  def put(context, params, now \\ DateTime.utc_now()) do
    with {:ok, attrs} <- Interests.normalize(params, disciplines()),
         {:ok, saved} <- Interests.put(context, attrs, now) do
      {:ok, present(saved)}
    end
  end

  defp disciplines do
    Organizations.box_vocabulary().discipline_groups |> Enum.flat_map(& &1.items)
  end

  defp present(interests), do: %{interests: Map.take(interests, [:disciplines, :level])}
end
