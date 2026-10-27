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
    verify_email: Palee.Email.Templates.VerifyEmail,
    security_account_deleted: Palee.Email.Templates.SecurityAccountDeleted,
    security_account_deletion_scheduled: Palee.Email.Templates.SecurityAccountDeletionScheduled,
    security_email_change_requested: Palee.Email.Templates.SecurityEmailChangeRequested,
    security_email_changed: Palee.Email.Templates.SecurityEmailChanged,
    security_new_sign_in: Palee.Email.Templates.SecurityNewSignIn,
    security_password_changed: Palee.Email.Templates.SecurityPasswordChanged,
    security_password_reset_completed: Palee.Email.Templates.SecurityPasswordResetCompleted,
    security_profile_added: Palee.Email.Templates.SecurityProfileAdded,
    security_recovery_code_used: Palee.Email.Templates.SecurityRecoveryCodeUsed,
    security_recovery_codes_regenerated: Palee.Email.Templates.SecurityRecoveryCodesRegenerated,
    security_recovery_codes_running_low: Palee.Email.Templates.SecurityRecoveryCodesRunningLow,
    security_signed_out_everywhere: Palee.Email.Templates.SecuritySignedOutEverywhere,
    password_reset: Palee.Email.Templates.PasswordReset
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
