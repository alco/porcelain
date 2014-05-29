defmodule Porcelain.Mixfile do
  use Mix.Project

  def project do
    [app: :porcelain,
     version: "0.0.2",
     elixir: "~> 0.14.0-dev"]
  end

  # Configuration for the OTP application
  def application do
    []
  end

  # no deps
  # --alco
end
