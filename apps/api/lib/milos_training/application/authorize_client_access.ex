defmodule MilosTraining.Application.AuthorizeClientAccess do
  @moduledoc """
  Whether the actor may use `capability` on one client (ADR-099/100): with
  scope `:all` any client of the gym; with scope `:own` only a client the
  coach coaches (an active coaching relationship).
  """

  alias MilosTraining.{Coaching, Organizations}

  def call(context, capability, client_user_id) do
    case Organizations.capability_scope(context, capability) do
      :all -> :ok
      scope when scope in [:own, :status] -> own_client(context, client_user_id)
      nil -> {:error, :forbidden}
    end
  end

  @doc "The client ids the actor may reach with `capability`, or `:all`."
  def client_ids(context, capability) do
    case Organizations.capability_scope(context, capability) do
      :all -> :all
      nil -> []
      _own -> Coaching.list_client_ids(context, context.user_id)
    end
  end

  defp own_client(context, client_user_id) do
    if Coaching.coaches?(context, context.user_id, client_user_id),
      do: :ok,
      else: {:error, :not_your_client}
  end
end
