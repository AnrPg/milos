defmodule MilosTraining.Application.GetPublicTheme do
  alias MilosTraining.Gamification

  def call do
    settings = Gamification.get_settings()
    {:ok, %{theme_slug: Map.get(settings, :theme_slug, "ember")}}
  end
end
