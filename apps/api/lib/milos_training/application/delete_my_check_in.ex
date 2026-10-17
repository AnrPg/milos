defmodule MilosTraining.Application.DeleteMyCheckIn do
  @moduledoc "The owner removes one of their Πώς νιώθω submissions (soft delete)."

  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.Wellbeing

  def call(%{user_id: user_id} = context, id, now \\ DateTime.utc_now()) do
    with {:ok, check_in} <-
           Wellbeing.with_tenant_context(context, fn ->
             Wellbeing.delete_check_in(id, user_id, now)
           end) do
      BroadcastUserSync.for_user(user_id, ["my_wellbeing"],
        reason: "check_in_deleted",
        payload: %{check_in_id: check_in.id}
      )

      :ok
    end
  end
end
