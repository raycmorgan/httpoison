defmodule HTTPoison.Mixfile do
  use Mix.Project

  def project do
    [ app: :httpoison,
      version: "0.0.3",
      elixir: "0.13.0-dev",
      deps: deps(Mix.env) ]
  end

  def application do
    [applications: [:hackney]]
  end

  defp deps(:prod) do
    [ { :hackney, github: "benoitc/hackney", tag: "0.11.1" } ]
  end

  defp deps(:test) do
    deps(:prod) ++ [ { :httparrot, github: "raycmorgan/httparrot", ref: "d82dd77" },
                     { :meck, github: "eproxus/meck", ref: "638e699" } ]
  end

  defp deps(_), do: deps(:prod)
end
