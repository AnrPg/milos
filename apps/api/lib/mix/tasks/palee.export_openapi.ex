defmodule Mix.Tasks.Palee.ExportOpenapi do
  use Mix.Task

  @shortdoc "Exports the OpenAPI spec to a JSON file (sorted keys, see ADR-134)"

  @impl Mix.Task
  def run([output_path]) do
    Mix.Task.run("loadpaths")
    Mix.Task.run("compile")

    output_path
    |> Path.expand()
    |> tap(&File.mkdir_p!(Path.dirname(&1)))
    |> File.write!(PaleeWeb.OpenApiExport.encode!(PaleeWeb.ApiSpec.spec()))
  end

  def run(_args) do
    Mix.raise("usage: mix palee.export_openapi PATH")
  end
end
