defmodule MilosTraining.Wellbeing.Ports.WellbeingStore do
  @callback report_injury(Ecto.UUID.t(), Ecto.UUID.t(), String.t(), map()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()}

  @callback mark_healed(Ecto.UUID.t(), Ecto.UUID.t(), Date.t() | nil) ::
              {:ok, map()} | {:error, term()}

  @callback update_injury(Ecto.UUID.t(), Ecto.UUID.t(), (map() ->
                                                           {:ok, map(), map()} | {:error, term()})) ::
              {:ok, map()} | {:error, term()}
  @callback reopen_injury(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, map()} | {:error, term()}

  @callback get_injury_for_user(Ecto.UUID.t(), Ecto.UUID.t()) :: map() | nil
  @callback list_injuries_for_user(Ecto.UUID.t()) :: [map()]
  @callback list_active_tenant_injuries_for_users([Ecto.UUID.t()]) :: [map()]
  @callback list_injuries(map()) :: [map()]
  @callback injury_summary(map()) :: map()

  # Πώς νιώθω check-ins (ADR-139, ADR-140 §2): owner-only rows, coach reads gated by rung.
  @callback create_check_in(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback delete_check_in(Ecto.UUID.t(), Ecto.UUID.t(), DateTime.t()) ::
              {:ok, map()} | {:error, :not_found}
  @callback get_check_in_for_user(Ecto.UUID.t(), Ecto.UUID.t()) :: map() | nil
  @callback set_check_in_visibility(Ecto.UUID.t(), Ecto.UUID.t(), String.t()) ::
              {:ok, map()} | {:error, :not_found | Ecto.Changeset.t()}
  @callback move_check_ins(Ecto.UUID.t(), [String.t()], String.t()) :: non_neg_integer()
  @callback list_check_in_items(Ecto.UUID.t(), term(), pos_integer(), term()) :: [map()]
  @callback list_injury_items(Ecto.UUID.t(), term(), pos_integer(), term()) :: [map()]
  @callback set_injury_visibility(Ecto.UUID.t(), Ecto.UUID.t(), String.t()) ::
              {:ok, map()} | {:error, :not_found | Ecto.Changeset.t()}
  @callback list_check_ins_between(Ecto.UUID.t(), DateTime.t(), DateTime.t()) :: [map()]
  @callback list_coach_visible_check_ins(Ecto.UUID.t(), Ecto.UUID.t()) :: [map()]
end
