defmodule Palee.Email.Templates.EmailChangeConfirmTest do
  use ExUnit.Case, async: true

  alias Palee.Email.Templates.EmailChangeConfirm

  @url "https://palee.app/confirm-email-change#token=abc"

  test "is security mail with the link in both bodies" do
    assert EmailChangeConfirm.category() == :security

    for locale <- ~w(en el ar) do
      assert EmailChangeConfirm.text(%{url: @url}, locale) =~ @url
      assert EmailChangeConfirm.html(%{url: @url}, locale) =~ "confirm-email-change#token=abc"
    end
  end

  test "reads natively in Greek" do
    assert EmailChangeConfirm.subject(%{url: @url}, "el") ==
             "Επιβεβαιώστε τη νέα σας διεύθυνση email"

    assert EmailChangeConfirm.text(%{url: @url}, "el") =~ "Ο σύνδεσμος ισχύει για 24 ώρες."
  end
end
