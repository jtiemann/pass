defmodule PassWeb.PasskeyControllerTest do
  use PassWeb.ConnCase, async: true

  describe "GET /users/passkeys/challenge" do
    setup :register_and_log_in_user

    test "returns creation options as JSON when the client asks for JSON", %{conn: conn} do
      # The browser ceremony fetches with Accept: application/json — this must
      # not be rejected by content negotiation.
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get(~p"/users/passkeys/challenge")

      body = json_response(conn, 200)
      assert is_binary(body["challenge"])
      assert body["rp"]["id"]
      assert body["user"]["name"]
      assert is_list(body["pubKeyCredParams"])
    end

    test "requires authentication" do
      conn = build_conn() |> get(~p"/users/passkeys/challenge")
      assert redirected_to(conn) =~ "/users/log-in"
    end
  end

  describe "sudo mode" do
    setup :register_and_log_in_user

    @tag token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
    test "passkey management requires a recent authentication", %{conn: conn} do
      conn = get(conn, ~p"/users/passkeys")
      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "re-authenticate"
    end

    test "passkey management is reachable right after logging in", %{conn: conn} do
      conn = get(conn, ~p"/users/passkeys")
      assert html_response(conn, 200) =~ "Your passkeys"
    end
  end
end
