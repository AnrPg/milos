defmodule MilosTraining.Application.GetClassTimer do
  @moduledoc "Reads a class timer: any active member of the gym may follow it."

  alias MilosTraining.Application.ClassTimerView

  @viewer_roles [:owner, :admin, :coach, :athlete, :member]

  def call(%{role: role} = context, slot_id) when role in @viewer_roles do
    with {:ok, view} <- ClassTimerView.load(context, slot_id) do
      {:ok, ClassTimerView.payload(view, DateTime.utc_now())}
    end
  end

  def call(_context, _slot_id), do: {:error, :forbidden}
end
