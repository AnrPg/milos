defmodule Palee.Fiscal.Templates do
  @moduledoc """
  Country document templates (ADR-245): a fiscal document rendered as
  printable HTML or as PDF, in the document's language or another one,
  with the mentions its country asks for, its VAT breakdown, the document
  it corrects, its myDATA MARK/UID/QR once reported (ADR-243) and, for
  Swiss and Liechtenstein invoices to be paid, the QR-bill.

  The document itself never changes; rendering reads it, the corrected
  document, its transmission and the seller's current bank details.
  """

  alias Palee.Fiscal
  alias Palee.Fiscal.{FiscalStore, Reporting}
  alias Palee.Fiscal.Domain.{DocumentHtml, DocumentLabels, DocumentPdf, DocumentView}

  @languages ~w(el en de fr it nl es)

  @doc "Languages a document can be rendered in."
  def languages, do: @languages

  @doc "The English texts to translate (`%{key => msgid}`, gettext domain `fiscal_documents`)."
  def label_messages, do: DocumentLabels.messages()

  @doc """
  `{:ok, %{view, document}}` for document `id`, or `{:error, :not_found}`
  / `{:error, :unsupported_language}`. `language` nil means the
  document's own language; `labels_for` gets the language and returns the
  translated labels (`label_messages/0` keys).
  """
  def view(context, id, language, labels_for) when is_function(labels_for, 1) do
    with %{} = document <- Fiscal.get_document(context, id) || {:error, :not_found},
         {:ok, language} <- language(language, document) do
      labels = labels_for.(language)

      original =
        document.corrects_document_id &&
          Fiscal.get_document(context, document.corrects_document_id)

      transmission = context |> Reporting.transmissions_for([document.id]) |> Map.get(document.id)

      view =
        DocumentView.build(document,
          labels: labels,
          language: language,
          original: original,
          transmission: transmission,
          identity: FiscalStore.get_identity(context)
        )

      {:ok, %{view: view, document: document}}
    end
  end

  @doc "The language a render uses (the document's when nil)."
  def language(nil, document), do: language(document.language, document)
  def language(language, _document) when language in @languages, do: {:ok, language}
  def language(_language, _document), do: {:error, :unsupported_language}

  def html(view), do: DocumentHtml.render(view)

  def pdf(view, fonts, %{issued_at: issued_at}),
    do: DocumentPdf.render(view, fonts, created_at: issued_at)
end
