defmodule MilosTraining.Wellbeing.Ports.WellbeingStore do
  @callback report_injury(Ecto.UUID.t(), Ecto.UUID.t(), String.t(), map()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()}

  @callback mark_healed(Ecto.UUID.t(), Ecto.UUID.t(), Date.t() | nil) ::
              {:ok, map()} | {:error, term()}

  @callback get_injury_for_user(Ecto.UUID.t(), Ecto.UUID.t()) :: map() | nil
  @callback list_injuries_for_user(Ecto.UUID.t()) :: [map()]
  @callback list_injuries(map()) :: [map()]
  @callback injury_summary(map()) :: map()
end
