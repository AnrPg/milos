defmodule Palee.Email.Templates do
  @moduledoc """
  The registry of email kinds (ADR-203): each kind atom names the
  `Palee.Email.Template` module that renders it. Adding an email is a
  template module plus one line here; keep the list sorted by kind.

  `config :palee, :email_templates_extra, %{kind => module}` adds kinds
  (tests register their sample templates this way).
  """

  @templates %{
    business_activation_link: Palee.Email.Templates.BusinessActivationLink,
    corporate_invoice_issued: Palee.Email.Templates.CorporateInvoiceIssued,
    corporate_invoice_reminder: Palee.Email.Templates.CorporateInvoiceReminder,
    verify_email: Palee.Email.Templates.VerifyEmail
  }

  @doc "Every kind and its template."
  def all, do: Map.merge(@templates, Application.get_env(:palee, :email_templates_extra, %{}))

  @doc "The kinds Palee can send."
  def kinds, do: all() |> Map.keys() |> Enum.sort()

  @doc "`{:ok, module}` for a known kind (atom, or its stored name), else `{:error, :unknown_kind}`."
  def fetch(kind) when is_atom(kind) do
    case Map.fetch(all(), kind) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unknown_kind}
    end
  end

  def fetch(kind) when is_binary(kind) do
    case Enum.find(all(), fn {known, _module} -> Atom.to_string(known) == kind end) do
      {_kind, module} -> {:ok, module}
      nil -> {:error, :unknown_kind}
    end
  end

  def fetch(_kind), do: {:error, :unknown_kind}
end
