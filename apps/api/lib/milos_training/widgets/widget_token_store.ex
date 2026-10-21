defmodule MilosTraining.Widgets.WidgetTokenStore do
  @moduledoc "Dispatches the widget token port to the configured adapter, in the person's session (ADR-173)."

  @behaviour MilosTraining.Widgets.Ports.WidgetTokenStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :widget_token_store)

  defp scoped(user_id, function, args),
    do: RepoContext.run(%{user_id: user_id}, fn -> apply(adapter(), function, args) end)

  @impl true
  def create_widget_token(%{user_id: user_id} = attrs),
    do: scoped(user_id, :create_widget_token, [attrs])

  @impl true
  def get_widget_token(user_id, id), do: scoped(user_id, :get_widget_token, [user_id, id])

  @impl true
  def delete_widget_token(user_id, id), do: scoped(user_id, :delete_widget_token, [user_id, id])

  @impl true
  def delete_widget_tokens_beyond(user_id, keep),
    do: scoped(user_id, :delete_widget_tokens_beyond, [user_id, keep])
end
