defmodule Palee.Localization do
  @moduledoc false

  def translate(locale, message, bindings \\ %{}, domain \\ "notifications") do
    adapter().translate(locale, domain, message, bindings)
  end

  defp adapter do
    Application.get_env(
      :palee,
      :localization_adapter,
      Palee.Infrastructure.Localization.GettextAdapter
    )
  end
end
