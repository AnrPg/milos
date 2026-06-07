defmodule Mix.Tasks.Milos.ExportOpenapi do
  use Mix.Task

  @shortdoc "Exports the OpenAPI spec to a JSON file"

  @impl Mix.Task
  def run([output_path]) do
    Mix.Task.run("loadpaths")
    Mix.Task.run("compile")

    output_path
    |> Path.expand()
    |> tap(&File.mkdir_p!(Path.dirname(&1)))
    |> File.write!(Jason.encode_to_iodata!(MilosTrainingWeb.ApiSpec.spec(), pretty: true))
  end

  def run(_args) do
    Mix.raise("usage: mix milos.export_openapi PATH")
  end
end
