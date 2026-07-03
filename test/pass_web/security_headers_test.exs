defmodule PassWeb.SecurityHeadersTest do
  use PassWeb.ConnCase, async: true

  test "browser responses carry a nonce-based Content-Security-Policy", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert [policy] = get_resp_header(conn, "content-security-policy")
    assert policy =~ "default-src 'self'"
    assert [_, nonce] = Regex.run(~r/'nonce-([^']+)'/, policy)

    # The inline theme script in the root layout must carry the same nonce,
    # otherwise the theme bootstrapper is blocked.
    assert html_response(conn, 200) =~ ~s(nonce="#{nonce}")
  end
end
