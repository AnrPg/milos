defmodule Palee.Application.Fiscal.FiscalDocumentRendering do
  @moduledoc """
  Staff › Fiscal › a document as PDF or printable HTML (ADR-245), in the
  document's language or the one asked for (`el en de fr it nl es`).
  Labels come from the `fiscal_documents` gettext domain; the PDF embeds
  Liberation Sans.
  """

  alias Palee.Fiscal
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

  @doc """
  «Αποστολή με email» (ADR-265): sends the document's PDF to `to`, or to
  the buyer's email printed on it, through the email outbox. Rendered in
  the document's language (or `language`). Idempotent by
  `idempotency_key`; journaled once per send; throttled per address by the
  outbox (`:throttled`), refused for a demo business (`:not_live`).

  `{:ok, %{id, status, to, recipient}, :queued | :replayed}` or
  `{:error, reason}` (`:no_recipient`, `:invalid_address`, ...).
  """
  def email(context, id, params, now \\ DateTime.utc_now()) do
    with {:ok, key} <- email_key(params["idempotency_key"] || params[:idempotency_key]),
         {:ok, language} <- requested(params["language"] || params[:language]),
         {:ok, %{view: view, document: document}} <-
           Templates.view(context, id, language, &labels/1),
         {:ok, to, recipient} <- recipient(params["to"] || params[:to], document),
         outbox_key = "fiscal_document:#{document.id}:#{key}" do
      outbox_key
      |> Palee.Email.list_by_idempotency_prefix()
      |> Enum.find(&(&1.idempotency_key == outbox_key))
      |> case do
        %{} = existing ->
          {:ok, sent(existing, to, recipient), :replayed}

        nil ->
          send_document(context, view, document, to, recipient, outbox_key, now)
      end
    end
  end

  defp send_document(context, view, document, to, recipient, outbox_key, now) do
    locale = view.language

    assigns = %{
      business: business_name(document.seller),
      title: view.title,
      number: document.number,
      issue_date: view.issue_date_text,
      total: view.gross_text
    }

    attachment = %{
      filename: "#{document.number}.pdf",
      content_type: "application/pdf",
      data: Templates.pdf(view, Fonts.sans(), document)
    }

    send = fn ->
      with {:ok, message} <-
             Palee.Email.enqueue(:fiscal_document, to, assigns,
               locale: locale,
               organization_id: context.organization_id,
               user_id: Map.get(context, :user_id),
               idempotency_key: outbox_key,
               attachments: [attachment],
               now: now
             ) do
        {:ok,
         %{
           message: message,
           recipient: recipient,
           recipient_digest: digest(to),
           message_id: message.id,
           language: locale
         }}
      end
    end

    with {:ok, %{message: message}} <-
           Fiscal.email_document(context, document, send, Map.get(context, :user_id), now) do
      {:ok, sent(message, to, recipient), :queued}
    end
  end

  defp email_key(key) when is_binary(key) and byte_size(key) in 8..120, do: {:ok, key}
  defp email_key(_key), do: {:error, :idempotency_key_required}

  defp recipient(to, document) when is_binary(to) do
    case String.trim(to) do
      "" -> recipient(nil, document)
      address -> {:ok, address, "address"}
    end
  end

  defp recipient(_none, document) do
    case buyer_email(document.buyer) do
      nil -> {:error, :no_recipient}
      email -> {:ok, email, "buyer"}
    end
  end

  defp buyer_email(%{} = buyer) do
    case buyer["email"] || buyer[:email] do
      email when is_binary(email) and email != "" -> email
      _none -> nil
    end
  end

  defp buyer_email(_buyer), do: nil

  defp business_name(seller) do
    seller["trade_name"] || seller[:trade_name] || seller["legal_name"] || seller[:legal_name] ||
      ""
  end

  defp digest(address),
    do:
      :crypto.hash(:sha256, address |> String.trim() |> String.downcase())
      |> Base.encode16(case: :lower)

  defp sent(message, to, recipient),
    do: %{
      id: message.id,
      status: message.status,
      to: String.downcase(String.trim(to)),
      recipient: recipient
    }

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
