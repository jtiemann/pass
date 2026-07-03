defmodule PassWeb.DocumentController do
  @moduledoc """
  Secure download of an asset's encrypted documents. Requires an authenticated
  user; the file is decrypted on the fly and sent as an attachment (never served
  inline, to avoid rendering untrusted uploads in the browser).
  """
  use PassWeb, :controller

  alias Pass.{Audit, Vault}

  def download(conn, %{"asset_id" => asset_id, "id" => id}) do
    asset = Vault.get_asset!(asset_id)
    document = Vault.get_document!(asset, id)

    Audit.log(conn.assigns.current_scope, "document.downloaded",
      entity_type: "document",
      entity_id: document.id,
      summary: document.filename
    )

    conn
    |> put_resp_content_type(document.content_type || "application/octet-stream")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> send_download({:binary, document.data},
      filename: sanitize_filename(document.filename),
      disposition: :attachment
    )
  end

  # Strip anything that could break the Content-Disposition header or path.
  defp sanitize_filename(name) do
    name
    |> Path.basename()
    |> String.replace(~r/[\r\n"\\]/, "")
    |> case do
      "" -> "download"
      clean -> clean
    end
  end
end
