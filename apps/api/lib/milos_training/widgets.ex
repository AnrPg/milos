defmodule MilosTraining.Widgets do
  @moduledoc """
  Widgets context (ADR-173): the app installs whose home-screen widgets
  («+1 νερό», Σήμερα, Check-in) read a small snapshot with a signed token.
  """

  alias MilosTraining.Widgets.{WidgetToken, WidgetTokenStore}

  def platforms, do: WidgetToken.platforms()

  def create_token(attrs), do: WidgetTokenStore.create_widget_token(attrs)
  def get_token(user_id, id), do: WidgetTokenStore.get_widget_token(user_id, id)
  def delete_token(user_id, id), do: WidgetTokenStore.delete_widget_token(user_id, id)

  @doc "Keeps the person's `keep` newest installs and forgets the rest."
  def prune_tokens(user_id, keep), do: WidgetTokenStore.delete_widget_tokens_beyond(user_id, keep)
end
