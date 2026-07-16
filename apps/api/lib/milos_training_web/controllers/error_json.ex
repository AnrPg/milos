defmodule MilosTrainingWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  # If you want to customize a particular status code,
  # you may add your own clauses, such as:
  #
  # def render("500.json", _assigns) do
  #   %{errors: %{detail: "Internal Server Error"}}
  # end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
  def render(template, _assigns) do
    status = Phoenix.Controller.status_message_from_template(template)

    %{
      code: template |> String.trim_trailing(".json") |> status_code(),
      error: status
    }
  end

  defp status_code("401"), do: "unauthorized"
  defp status_code("403"), do: "forbidden"
  defp status_code("404"), do: "not_found"
  defp status_code("422"), do: "validation_failed"
  defp status_code("429"), do: "rate_limited"
  defp status_code(code) when code in ["500", "502", "503", "504"], do: "unexpected_server_error"
  defp status_code(_code), do: "request_failed"
end
