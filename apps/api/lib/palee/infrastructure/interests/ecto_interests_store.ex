defmodule Palee.Infrastructure.Interests.EctoInterestsStore do
  @moduledoc "Ecto adapter of a person's interests (ADR-183)."

  @behaviour Palee.Interests.Ports.InterestsStore

  alias Palee.Interests.AccountInterests
  alias Palee.Repo

  @impl true
  def get(%{user_id: user_id}) do
    case Repo.get(AccountInterests, user_id) do
      nil -> nil
      row -> present(row)
    end
  end

  @impl true
  def put(%{user_id: user_id}, %{disciplines: disciplines, level: level}, now) do
    row = %{
      user_id: user_id,
      disciplines: disciplines,
      level: level,
      inserted_at: now,
      updated_at: now
    }

    {1, [saved]} =
      Repo.insert_all(AccountInterests, [row],
        on_conflict: {:replace, [:disciplines, :level, :updated_at]},
        conflict_target: :user_id,
        returning: true
      )

    {:ok, present(saved)}
  end

  defp present(row), do: %{disciplines: row.disciplines, level: row.level}
end
