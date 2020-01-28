defmodule Ueberauth.Strategy.Feishu.OAuth do
  @moduledoc """
  An implementation of OAuth2 for feishu.

  To add your `client_id` and `client_secret` include these values in your configuration.

      config :ueberauth, Ueberauth.Strategy.Feishu.OAuth,
        client_id: System.get_env("FEISHU_APPID"),
        client_secret: System.get_env("FEISHU_SECRET")
  """
  use OAuth2.Strategy

  @defaults [
    strategy: __MODULE__,
    site: "https://open.feishu.cn/",
    authorize_url: "https://open.feishu.cn/connect/qrconnect/page/sso",
    token_url: "https://open.feishu.cn/connect/qrconnect/oauth2/access_token/"
  ]

  @doc """
  Construct a client for requests to Feishu.

  Optionally include any OAuth2 options here to be merged with the defaults.

      Ueberauth.Strategy.Feishu.OAuth.client(redirect_uri: "http://localhost:4000/auth/feishu/callback")

  This will be setup automatically for you in `Ueberauth.Strategy.Feishu`.
  These options are only useful for usage outside the normal callback phase of Ueberauth.
  """
  def client(opts \\ []) do
    config =
    :ueberauth
    |> Application.fetch_env!(Ueberauth.Strategy.Feishu.OAuth)
    |> check_config_key_exists(:client_id)
    |> check_config_key_exists(:client_secret)

    client_opts =
      @defaults
      |> Keyword.merge(config)
      |> Keyword.merge(opts)

    OAuth2.Client.new(client_opts)
  end

  @doc """
  Provides the authorize url for the request phase of Ueberauth. No need to call this usually.
  """
  def authorize_url!(params \\ [], opts \\ []) do
    opts
    |> client
    |> OAuth2.Client.authorize_url!(params)
  end

  def get(token, url, headers \\ [], opts \\ []) do
    access_token = token.access_token

    headers = 
      headers
      |> Keyword.put(:authentication, "Bearer " <> access_token)
      |> Keyword.put(:"content-type", "application/json")

    url = ~s/#{url}/
    [token: token]
    |> client
    |> OAuth2.Client.get(url, headers, opts)
    |> IO.inspect(label: "Feishu::OAuth.get response", pretty: true)
  end

  def get_token!(params \\ [], options \\ []) do
    headers        = 
      Keyword.get(options, :headers, [])
    options        = Keyword.get(options, :options, [])
    client_options = Keyword.get(options, :client_options, [])
    client         = OAuth2.Client.get_token!(client(client_options), params, headers, options)
    client.token
  end

  # Strategy Callbacks

  def authorize_url(client, params) do
    client
    |> put_param(:app_id, client.client_id)
    |> put_param(:redirect_uri, client.redirect_uri)
    |> OAuth2.Strategy.AuthCode.authorize_url(params)
  end

  def get_token(client, params, headers) do
    {code, params} = Keyword.pop(params, :code, client.params["code"])
    unless code do
      raise OAuth2.Error, reason: "Missing required key `code` for `#{inspect __MODULE__}`"
    end

    client
    |> put_param(:app_id, client.client_id)
    |> put_param(:code, code)
    |> put_param(:app_secret, client.client_secret)
    |> put_header("Accept", "application/json")
    |> put_header("content-type", "application/json")
    |> OAuth2.Strategy.AuthCode.get_token(params, headers)
    |> IO.inspect(label: "feishu_oauth_get_token", pretty: true)
  end

  defp check_config_key_exists(config, key) when is_list(config) do
    unless Keyword.has_key?(config, key) do
      raise "#{inspect (key)} missing from config :ueberauth, Ueberauth.Strategy.Feishu"
    end
    config
  end
  defp check_config_key_exists(_, _) do
    raise "Config :ueberauth, Ueberauth.Strategy.Feishu is not a keyword list, as expected"
  end
end
