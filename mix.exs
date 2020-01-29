defmodule Ueberauth.Feishu.Mixfile do
  use Mix.Project

  @version "0.0.1"

  def project do
    [app: :ueberauth_feishu,
     version: @version,
     name: "Ueberauth Feishu",
     package: package(),
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     source_url: "https://github.com/edwardzhou/ueberauth_feishu",
     homepage_url: "https://github.com/edwardzhou/ueberauth_feishu",
     description: description(),
     deps: deps(),
     docs: docs()]
  end

  def application do
    [applications: [:logger, :ueberauth, :oauth2]]
  end

  defp deps do
    [
    #  {:oauth2, "~> 2.0"},
     {:oauth2, "~> 0.9"},
     {:ueberauth, "~> 0.6"},
     {:jason, "~> 1.0"},
     # dev/test only dependencies
     {:credo, "~> 1.2", only: [:dev, :test]},

     # docs dependencies
     {:earmark, ">= 0.0.0", only: [:dev, :docs]},
     {:ex_doc, ">= 0.0.0", only: [:dev, :docs]}
    ]
  end

  defp docs do
    [extras: ["README.md"]]
  end

  defp description do
    "An Ueberauth strategy for using Feishu to authenticate your users."
  end

  defp package do
    [files: ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: ["edwardzhou"],
      licenses: ["MIT"],
      links: %{"GitHub": "https://github.com/edwardzhou/ueberauth_feishu"}]
  end
end
