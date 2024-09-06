defmodule GhaAction do
  @moduledoc """
  GhaAction convert custom GitHub Action into Dagger module.
  """

  def convert(path) do
    action_yaml =
      Path.join(path, "action.yml")
      |> YamlElixir.read_from_file!()

    name = action_name(action_yaml)

    case Dagger.with_connection(&generate_module(&1, name), connect_timeout: :timer.minutes(2)) do
      {:ok, _} -> :ok
      {:error, exception} -> exception |> Exception.message() |> IO.puts()
    end
  end

  defp action_name(%{"name" => name}) do
    name
    |> String.replace(" ", "-")
    |> String.replace("_", "-")
  end

  defp generate_module(dag, name) do
    dockerd =
      dag
      |> Dagger.Client.container()
      |> Dagger.Container.from("docker:27-dind")
      |> Dagger.Container.without_entrypoint()
      |> Dagger.Container.with_exposed_port(2375)
      |> Dagger.Container.with_exec(
        [
          "dockerd",
          "--host=tcp://0.0.0.0:2375",
          "--host=unix:///var/run/docker.sock",
          "--tls=false"
        ],
        insecure_root_capabilities: true
      )
      |> Dagger.Container.as_service()

    dag
    |> Dagger.Client.container()
    |> Dagger.Container.from("docker:27.2.0-cli")
    |> Dagger.Container.with_service_binding("dockerd", dockerd)
    |> Dagger.Container.with_env_variable("DOCKER_HOST", "tcp://dockerd:2375")
    |> Dagger.Container.with_exec(~w"apk add curl git")
    |> Dagger.Container.with_exec([
      "sh",
      "-c",
      "curl -fsSL https://dl.dagger.io/dagger/install.sh | sh"
    ])
    |> Dagger.Container.with_workdir("/dagger")
    |> Dagger.Container.with_exec(["dagger", "init", "--sdk=elixir", name])
    |> Dagger.Container.directory(name)
    |> Dagger.Directory.export(name)
  end
end
