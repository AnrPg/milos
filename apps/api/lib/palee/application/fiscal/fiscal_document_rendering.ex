defmodule Palee.Application.Fiscal.FiscalDocumentRendering do
  @moduledoc """
  Staff › Fiscal › a document as PDF or printable HTML (ADR-245), in the
  document's language or the one asked for (`el en de fr it nl es`).
  Labels come from the `fiscal_documents` gettext domain; the PDF embeds
  Liberation Sans.
  """

  alias Palee.Fiscal.Templates
  alias Palee.Localization
  alias Palee.Pdf.Fonts

  @doc """
  `{:ok, %{content, content_type, filename}}`, `{:error, :not_found}` or
  `{:error, :unsupported_language}`. `format` is `:pdf` or `:html`.
  """
  def call(context, id, format, language \\ nil) when format in [:pdf, :html] do
    with {:ok, language} <- requested(language),
         {:ok, %{view: view, document: document}} <-
           Templates.view(context, id, language, &labels/1) do
      case format do
        :pdf ->
          {:ok,
           %{
             content: Templates.pdf(view, Fonts.sans(), document),
             content_type: "application/pdf",
             filename: "#{document.number}.pdf"
           }}

        :html ->
          {:ok,
           %{
             content: Templates.html(view),
             content_type: "text/html; charset=utf-8",
             filename: "#{document.number}.html"
           }}
      end
    end
  end

  defp requested(nil), do: {:ok, nil}
  defp requested(""), do: {:ok, nil}

  defp requested(language) do
    if language in Templates.languages(),
      do: {:ok, language},
      else: {:error, :unsupported_language}
  end

  defp labels(language) do
    Map.new(Templates.label_messages(), fn {key, message} ->
      {key, Localization.translate(language, message, %{}, "fiscal_documents")}
    end)
  end
end
