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
end
