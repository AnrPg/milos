defmodule Palee.Pdf.Fonts do
  @moduledoc """
  The fonts Palee embeds in PDFs (ADR-245): Liberation Sans regular and bold
  (SIL Open Font License 1.1, `priv/fonts/LICENSE-LiberationSans.txt`).
  Liberation Sans has Latin, Greek and Cyrillic, and is one of the four
  typefaces the Swiss QR-bill allows (SIX IG v2.4 §3.4).

  Parsed once per node and kept in `:persistent_term`.
  """

  alias Palee.Pdf.TrueType

  @files %{regular: "LiberationSans-Regular.ttf", bold: "LiberationSans-Bold.ttf"}

  @doc "`%{regular: font, bold: font}`."
  def sans do
    case :persistent_term.get({__MODULE__, :sans}, nil) do
      nil ->
        fonts = Map.new(@files, fn {key, file} -> {key, load(file)} end)
        :persistent_term.put({__MODULE__, :sans}, fonts)
        fonts

      fonts ->
        fonts
    end
  end

  defp load(file) do
    :palee
    |> :code.priv_dir()
    |> Path.join(["fonts/", file])
    |> File.read!()
    |> TrueType.parse()
  end
end
