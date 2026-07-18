defmodule MilosTrainingWeb.MeControllerTest do
  use MilosTrainingWeb.ConnCase, async: true

  alias MilosTraining.Identity
  alias MilosTraining.Infrastructure.Auth.Guardian

  describe "PATCH /api/me/avatar" do
    test "rejects a missing avatar_key instead of clearing the avatar implicitly", %{conn: conn} do
      {:ok, user} =
        Identity.register(%{
          nickname: "avatar_contract_member",
          password: "S3cur3P@ss!",
          role: :member
        })

      conn
      |> put_bearer_token(user)
      |> patch("/api/me/avatar", Jason.encode!(%{}))
      |> json_response(422)

      assert Identity.find_by_id(user.id).avatar_url == nil
    end
  end

  describe "PATCH /api/me/profile language preference" do
    test "persists a supported locale and returns it in the profile response", %{conn: conn} do
      {:ok, user} =
        Identity.register(%{
          nickname: "polyglot_member",
          password: "S3cur3P@ss!",
          role: :member
        })

      {:ok, access_token, _claims} =
        Guardian.encode_and_sign(user, %{"sv" => Map.get(user, :security_version, 1)},
          token_type: "access"
        )

      body =
        conn
        |> put_req_header("authorization", "Bearer " <> access_token)
        |> put_req_header("content-type", "application/json")
        |> patch("/api/me/profile", Jason.encode!(%{preferred_locale: "ar"}))
        |> json_response(200)

      assert body["user"]["preferred_locale"] == "ar"
      assert Identity.find_by_id(user.id).preferred_locale == "ar"
    end

    test "rejects an unsupported locale without changing the preference", %{conn: conn} do
      {:ok, user} =
        Identity.register(%{
          nickname: "locale_guard",
          password: "S3cur3P@ss!",
          role: :athlete
        })

      {:ok, access_token, _claims} =
        Guardian.encode_and_sign(user, %{"sv" => Map.get(user, :security_version, 1)},
          token_type: "access"
        )

      conn
      |> put_req_header("authorization", "Bearer " <> access_token)
      |> put_req_header("content-type", "application/json")
      |> patch("/api/me/profile", Jason.encode!(%{preferred_locale: "pt-BR"}))
      |> json_response(422)

      assert Identity.find_by_id(user.id).preferred_locale == "en"
    end
  end
end
