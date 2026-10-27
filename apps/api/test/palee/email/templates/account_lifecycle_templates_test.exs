defmodule Palee.Email.Templates.AccountLifecycleTemplatesTest do
  @moduledoc "ADR-211: the sign-up attempt and deletion confirmation emails, in every locale."
  use ExUnit.Case, async: true

  alias Palee.Email.Templates.{AccountDeletionConfirm, SignupAttemptExisting}

  @locales ~w(ar bg de el en es fr he it nl pt_PT ru)
  @attempt %{sign_in_url: "https://palee.app/login", reset_url: "https://palee.app/forgot-password"}
  @confirm %{
    scope: :profile,
    handle: "maria.k",
    url: "https://palee.app/account-deletion/confirm#token=abc",
    grace_days: 7
  }

  test "every locale renders both emails with every placeholder filled" do
    for locale <- @locales,
        {module, assigns} <- [{SignupAttemptExisting, @attempt}, {AccountDeletionConfirm, @confirm}] do
      subject = module.subject(assigns, locale)
      text = module.text(assigns, locale)
      html = module.html(assigns, locale)

      for rendered <- [subject, text, html] do
        refute rendered =~ "%{", "#{locale} #{inspect(module)} left a placeholder"
      end

      if locale != "en" do
        refute subject == module.subject(assigns, "en"), "#{locale} #{inspect(module)} untranslated"
      end
    end
  end

  test "the sign-up attempt links to sign-in and reset, and carries no token" do
    text = SignupAttemptExisting.text(@attempt, "el")
    assert text =~ "Κάποιος προσπάθησε να δημιουργήσει λογαριασμό στο Palee"
    assert text =~ "https://palee.app/login"
    assert text =~ "https://palee.app/forgot-password"
    refute text =~ "token"
    assert SignupAttemptExisting.category() == :account
    assert %{max_per_day: 3} = SignupAttemptExisting.throttle()
  end

  test "the deletion confirmation names the profile or the whole login" do
    assert AccountDeletionConfirm.text(@confirm, "en") =~ "delete your profile @maria.k."

    assert AccountDeletionConfirm.text(%{@confirm | scope: :login}, "el") =~
             "Ζητήσατε να διαγραφεί η σύνδεσή σας μαζί με όλα τα προφίλ της."

    html = AccountDeletionConfirm.html(@confirm, "he")
    assert html =~ ~s(dir="rtl")
    assert html =~ "https://palee.app/account-deletion/confirm#token=abc"
    assert AccountDeletionConfirm.category() == :security
  end
end
