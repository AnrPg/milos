defmodule MilosTraining.Localization do
  @moduledoc false

  def translate(locale, message, bindings \\ %{}, domain \\ "notifications") do
    adapter().translate(locale, domain, message, bindings)
  end

  defp adapter do
    Application.get_env(
      :milos_training,
      :localization_adapter,
      MilosTraining.Infrastructure.Localization.GettextAdapter
    )
  end
end
