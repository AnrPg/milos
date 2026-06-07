defmodule MilosTraining.Identity.Account do
  @moduledoc false

  @enforce_keys [:id, :nickname, :role]
  defstruct [:id, :nickname, :role, :password_hash, :leaderboard_opt_in]
end
