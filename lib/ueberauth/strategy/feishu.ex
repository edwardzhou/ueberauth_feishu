defmodule Ueberauth.Strategy.Feishu do
  @moduledoc """
  Provides an Ueberauth strategy for authenticating with Feishu.

  ### Setup

  Include the provider in your configuration for Ueberauth

      config :ueberauth, Ueberauth,
        providers: [
          feishu: { Ueberauth.Strategy.Feishu, [] }
        ]

  Then include the configuration for feishu.

      config :ueberauth, Ueberauth.Strategy.Feishu.OAuth,
        client_id: System.get_env("WECHAT_MINIAPP_APPID"),
        client_secret: System.get_env("WECHAT_MINIAPP_SECRET")

  If you haven't already, create a pipeline and setup routes for your callback handler

      pipeline :auth do
        Ueberauth.plug "/auth"
      end

      scope "/auth" do
        pipe_through [:browser, :auth]

        get "/:provider/callback", AuthController, :callback
      end


  Create an endpoint for the callback where you will handle the `Ueberauth.Auth` struct

      defmodule MyApp.AuthController do
        use MyApp.Web, :controller

        def callback_phase(%{ assigns: %{ ueberauth_failure: fails } } = conn, _params) do
          # do things with the failure
        end

        def callback_phase(%{ assigns: %{ ueberauth_auth: auth } } = conn, params) do
          # do things with the auth
        end
      end

  """
  use Ueberauth.Strategy,
    uid_field: :openId,
    default_scope: "snsapi_userinfo",
    oauth2_module: Ueberauth.Strategy.Feishu.OAuth

  alias Ueberauth.Auth.Info
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra

  @doc """
  Handles the initial redirect to the feishu authentication page.

  To customize the scope (permissions) that are requested by feishu include them as part of your url:

      "/auth/feishu?scope=snsapi_userinfo"

  You can also include a `state` param that feishu will return to you.
  """
  def handle_request!(conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)
    send_redirect_uri = Keyword.get(options(conn), :send_redirect_uri, true)

    opts =
      if send_redirect_uri do
        [redirect_uri: callback_url(conn), scope: scopes]
      else
        [scope: scopes]
      end

    opts =
      if conn.params["state"], do: Keyword.put(opts, :state, conn.params["state"]), else: opts

    module = option(conn, :oauth2_module)
    redirect!(conn, apply(module, :authorize_url!, [opts]))
  end

  @doc """
  Enable test callback with code=test_code
  """
  def handle_callback!(%Plug.Conn{params: %{"code" => "test_code"}} = conn), do: conn

  @doc """
  Handles the callback from Feishu. When there is a failure from Feishu the failure is included in the
  `ueberauth_failure` struct. Otherwise the information returned from Feishu is returned in the `Ueberauth.Auth` struct.
  """
  def handle_callback!(%Plug.Conn{params: %{"code" => code} = params} = conn) do
    module = option(conn, :oauth2_module)
    token = apply(module, :get_token!, [[code: code]])

    if token.access_token == nil do
      set_errors!(conn, [
        error(token.other_params["error"], token.other_params["error_description"])
      ])
    else
      fetch_user(conn, token)
    end
  end

  @doc false
  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  @doc """
  Cleans up the private area of the connection used for passing the raw Feishu response around during the callback.
  """
  def handle_cleanup!(conn) do
    conn
    |> put_private(:feishu_user, nil)
    |> put_private(:feishu_token, nil)
  end

  @doc """
  Fetches the uid field from the Feishu response. This defaults to the option `uid_field` which in-turn defaults to `id`
  """
  def uid(conn) do
    user =
      conn
      |> option(:uid_field)
      |> to_string

    conn.private.feishu_user[user]
  end

  @doc """
  Includes the credentials from the Feishu response.
  """
  def credentials(conn) do
    token = conn.private.feishu_token
    scope_string = token.other_params["scope"] || ""
    scopes = String.split(scope_string, ",")

    %Credentials{
      token: token.access_token,
      refresh_token: "",
      expires_at: 0,
      token_type: "feishu",
      expires: false,
      scopes: scopes
    }
  end

  @doc """
  Fetches the fields to populate the info section of the `Ueberauth.Auth` struct.
  """
  def info(conn) do
    user = conn.private.feishu_user

    %Info{
      nickname: user["nickName"],
      image: user["avatarUrl"]
    }
  end

  @doc """
  Stores the raw information (including the token) obtained from the Feishu callback.
  """
  def extra(conn) do
    %Extra{
      raw_info: %{
        token: conn.private.feishu_token,
        user: conn.private.feishu_user
      }
    }
  end

  defp fetch_user(conn, token) do
    conn = put_private(conn, :feishu_token, token)
    # Will be better with Elixir 1.3 with/else
    miniapp_token = token.access_token |> Poison.decode!()

    result = with {:ok, _} <- verify_signature(conn, miniapp_token), 
          do: decrypt_data(conn, miniapp_token)
    
    case result do
      {:error, reason} ->
        set_errors!(conn, [error("data_invalid", reason)])
      {:ok, user_info} ->
        put_private(conn, :feishu_user, user_info)
    end
  end

  defp decrypt_data(%{params: params} = _conn, miniapp_token) do
    dec_key = miniapp_token["session_key"] |> Base.decode64!()
    iv_key = params["iv"] |> Base.decode64!()
    debase64_data = params["encrypted_data"] |> Base.decode64!()

    # decrypt with AES128
    binary_data = :crypto.block_decrypt(:aes_cbc128, dec_key, iv_key, debase64_data)
    # unpad
    to_remove = :binary.last(binary_data)
    case binary_data
          |> :binary.part(0, byte_size(binary_data) - to_remove)
          |> Poison.decode() do
      {:ok, data} -> 
        union_id = data[:unionId]
        {:ok, Map.put(data, "unionid", union_id)}
      _ ->
        {:error, :data_corrupted}      
    end
  end

  defp verify_signature(%{params: params} = _conn, miniapp_token) do
    signature = params["signature"]
    raw_data = params["raw_data"]
    session_key = miniapp_token["session_key"]

    sha1 = :crypto.hash(:sha, raw_data <> session_key)
            |> Base.encode16
            |> String.downcase
    case sha1 do
      ^signature ->
        {:ok, signature}
      _ ->
        {:error, :signature_not_matched}
    end
  end

  defp option(conn, key) do
    Keyword.get(options(conn), key, Keyword.get(default_options(), key))
  end
end
