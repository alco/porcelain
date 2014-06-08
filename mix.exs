defmodule Porcelain.Mixfile do
  use Mix.Project

  def project do
    [app: :porcelain,
     version: "1.0.0-alpha",
     elixir: "~> 0.13.3 or ~> 0.14.0"]
  end

  # Configuration for the OTP application
  def application do
    []
  end

  # no deps
  # --alco
end
