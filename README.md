# Überauth Feishu

> Feishu OAuth2 strategy for Überauth.

## Installation

1. Add `:ueberauth_feishu` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:ueberauth_feishu, github: "edwardzhou/ueberauth_feishu"}]
    end
    ```

1. Add the strategy to your applications:

    ```elixir
    def application do
      [applications: [:ueberauth_feishu]]
    end
    ```

1. Add Wechat to your Überauth configuration:

    ```elixir
    config :ueberauth, Ueberauth,
      providers: [
        feishu: {Ueberauth.Strategy.Feishu, []}
      ]
    ```

1.  Update your provider configuration:

    ```elixir
    config :ueberauth, Ueberauth.Strategy.Feishu.OAuth,
      client_id: System.get_env("FEISHU_APPID"),
      client_secret: System.get_env("FEISHU_SECRET")
    ```

1.  Include the Überauth plug in your controller:

    ```elixir
    defmodule MyApp.AuthController do
      use MyApp.Web, :controller

      pipeline :browser do
        plug Ueberauth
        ...
       end
    end
    ```

1.  Create the request and callback routes if you haven't already:

    ```elixir
    scope "/auth", MyApp do
      pipe_through :browser

      get "/:provider/callback", AuthController, :callback
      post "/:provider/callback", AuthController, :callback
    end
    ```

1. You controller needs to implement callbacks to deal with `Ueberauth.Auth` and `Ueberauth.Failure` responses.

For an example implementation see the [Überauth Example](https://github.com/ueberauth/ueberauth_example) application.

## Calling
    get or post
    /auth/feishu/callback?code=<auth_code>

## Unit Test Support

  Authorization can be mock in unit test, with specific code "test_code".

  ** Example: **

  ```elixir
   describe "new github authentication" do
    test "create new user", %{conn: conn} do
      assert Accounts.find_authentication(@github_params.uid) == nil

      conn =
        conn
        |> assign(:ueberauth_auth, @github_params)
        |> get(auth_path(conn, :callback, :github), %{"code" => "test_code"})

      assert html_response(conn, 302)
      assert Accounts.find_authentication(@github_params.uid) != nil
    end
  end 
  ```
