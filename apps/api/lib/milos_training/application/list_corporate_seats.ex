defmodule MilosTraining.Application.ListCorporateSeats do
  @moduledoc "A corporate client's seats with the employees' nicknames (ADR-098)."

  alias MilosTraining.{Finance, Identity}

  def call(context, client_id) do
    seats = Finance.list_corporate_seats(context, client_id)

    nicknames =
      seats |> Enum.map(& &1.user_id) |> Identity.list_by_ids() |> Map.new(&{&1.id, &1.nickname})

    Enum.map(seats, &Map.put(&1, :nickname, Map.get(nicknames, &1.user_id)))
  end
end
