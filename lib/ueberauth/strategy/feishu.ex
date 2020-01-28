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
        client_id: System.get_env("FEISHU_APPID"),
        client_secret: System.get_env("SEISHU_SECRET")

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
    uid_field: :open_id,
    default_scope: "snsapi_userinfo",
    oauth2_module: Ueberauth.Strategy.Feishu.OAuth

  alias Ueberauth.Auth.Info
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra

  @user_info_url "https://open.feishu.cn/open-apis/authen/v1/user_info"

  @doc """
  Handles the initial redirect to the feishu authentication page.

      "/auth/feishu"

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
    token = 
      apply(module, :get_token!, [[code: code]])
      |> IO.inspect(label: "Feishu::Strategy.handle_callback response", pretty: true)

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
      refresh_token: token.refresh_token,
      expires_at: token.expires_at,
      token_type: token.token_type,
      expires: false,
      scopes: scopes,
      other: token.other_params
    }
  end

  @doc """
  Fetches the fields to populate the info section of the `Ueberauth.Auth` struct.
  """
  def info(conn) do
    user = conn.private.feishu_user

    %Info{
      nickname: user["name"],
      name: user["name"],
      image: user["avatar_url"],
      email: user["email"],
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
    token
    |> IO.inspect(label: "Feishu::Strategy.fetch_user token ", pretty: true)

    result = 
      conn
      |> option(:oauth2_module)
      |> apply(:get, [token, @user_info_url])
      |> IO.inspect(label: "get user info", pretty: true)

    case result do
      {:error, reason} ->
        set_errors!(conn, [error("data_invalid", reason)])
      {:ok, user_info} ->
        put_private(conn, :feishu_user, Map.merge(token.other_params, user_info.body["data"]))
    end
  end

  defp option(conn, key) do
    Keyword.get(options(conn), key, Keyword.get(default_options(), key))
  end
end
