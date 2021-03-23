defmodule Porcelain.Mixfile do
  use Mix.Project

  @source_url "https://github.com/alco/porcelain"
  @version "2.0.3"

  def project do
    [
      app: :porcelain,
      version: @version,
      elixir: "~> 1.3",
      deps: deps(),
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [
      applications: [:logger, :crypto],
      mod: {Porcelain.App, []}
    ]
  end

  def docs do
    [
      extras: ["CHANGELOG.md", "README.md"],
      main: "readme",
      source_url: @source_url,
      formatters: ["html"]
    ]
  end

  defp description do
    "Porcelain implements a saner approach to launching and communicating " <>
      "with external OS processes from Elixir. Built on top of Erlang's ports, " <>
      "it provides richer functionality and simpler API."
  end

  defp package do
    [
      description: description(),
      files: ["lib", "mix.exs", "README.md", "CHANGELOG.md", "LICENSE"],
      maintainers: ["Alexei Sholik"],
      licenses: ["MIT"],
      links: %{
        "Changelog" => "https://hexdocs.pm/porcelain",
        "GitHub" => @source_url
      }
    ]
  end

  defp deps do
    [
      {:ex_doc, "> 0.0.0", only: :dev, runtime: false}
    ]
  end
end
