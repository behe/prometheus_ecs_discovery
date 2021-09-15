defmodule Labels do
  defstruct [
    :task_arn,
    :task_name,
    :task_revision,
    :task_group,
    :cluster_arn,
    :container_name,
    :container_arn,
    :docker_image,
    :__metrics_path__
  ]
end

defmodule Service do
  defstruct targets: [], labels: %Labels{}
end

defmodule PrometheusEcsDiscovery do
  require Logger

  def config(config) do
    [
      http_client: HTTPoison,
      json_codec: Jason,
      access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
      region: System.get_env("AWS_REGION")
    ]
    |> Keyword.merge(config)
  end

  def prometheus_services(config \\ []) do
    Application.ensure_all_started(:prometheus_ecs_discovery)
    config = config(config)

    with {:ok, %{"clusterArns" => cluster_arns}} <- ExAws.ECS.list_clusters() |> ExAws.request(config),
         {:ok, tasks} <- describe_tasks(cluster_arns, config),
         {:ok, task_definitions_by_arn} <- task_definitions_by_arn(tasks, config) do
      services =
        tasks
        |> Enum.filter(fn task ->
          get_in(
            task_definitions_by_arn,
            [task["taskDefinitionArn"], "containerDefinitions", Access.at(0), "environment"]
          )
          |> Enum.find(fn env -> env["name"] == "PROMETHEUS_EXPORTER_PATH" end)
        end)
        |> Enum.map(fn task ->
          task_definition = get_in(task_definitions_by_arn, [task["taskDefinitionArn"]])
          container = get_in(task, ["containers", Access.at(0)])
          container_definition = get_in(task_definition, ["containerDefinitions", Access.at(0)])
          host = get_in(container, ["networkInterfaces", Access.at(0), "privateIpv4Address"])
          port = get_in(container_definition, ["portMappings", Access.at(0), "hostPort"])

          %Service{
            targets: ["#{host}:#{port}"],
            labels: %Labels{
              task_arn: get_in(task, ["taskArn"]),
              task_name: get_in(task_definition, ["family"]),
              task_revision: get_in(task_definition, ["revision"]) |> to_string,
              task_group: get_in(task, ["group"]),
              cluster_arn: get_in(task, ["clusterArn"]),
              container_name: get_in(container, ["name"]),
              container_arn: get_in(container, ["containerArn"]),
              docker_image: get_in(container_definition, ["image"]),
              __metrics_path__:
                get_in(container_definition, ["environment"])
                |> Enum.find_value(fn
                  %{"name" => "PROMETHEUS_EXPORTER_PATH", "value" => path} -> path
                  _ -> false
                end)
            }
          }
        end)

      {:ok, services}
    else
      {:error, error} ->
        Logger.error(inspect(error))
        {:error, error}
    end
  end

  def to_yaml(services) do
    services
    |> Enum.map(fn service ->
      yaml =
        ["- targets:"] ++
          Enum.map(service.targets, fn target -> "  - #{target}" end) ++
          ["  labels:"] ++
          Enum.map(Map.from_struct(service.labels), fn {k, v} -> "    #{k}: #{inspect(v)}" end) ++ [""]

      Enum.join(yaml, "\n")
    end)
  end

  def disco do
    with {:ok, services} <- prometheus_services() do
      filename = "ecs_file_sd.yml"
      Logger.warn("Writing #{length(services)} discovered exporters to #{filename}")
      File.write!(filename, to_yaml(services))
    end
  end

  defp describe_tasks(cluster_arns, config) do
    Enum.reduce_while(cluster_arns, {:ok, []}, fn
      cluster_arn, {:ok, acc} ->
        case ExAws.ECS.list_tasks(cluster_arn) |> ExAws.request(config) do
          {:ok, %{"taskArns" => []}} ->
            {:cont, {:ok, acc}}

          {:ok, %{"taskArns" => tasks}} ->
            Logger.warn("Inspected cluster #{cluster_arn}, found #{length(tasks)} tasks")

            {:ok, %{"failures" => describe_failures, "tasks" => describe_tasks}} =
              ExAws.ECS.describe_tasks(cluster_arn, tasks, include: ["TAGS"])
              |> ExAws.request(config)

            Logger.warn("Described #{length(describe_tasks)} tasks in cluster #{cluster_arn}")

            if (describe_failure_length = length(describe_failures)) > 0 do
              Logger.error("Described #{describe_failure_length} failures in cluster #{cluster_arn}")
            end

            {:cont, {:ok, acc ++ describe_tasks}}

          error ->
            Logger.warn(inspect(error))
            {:halt, error}
        end
    end)
  end

  defp task_definitions_by_arn(tasks, config) do
    tasks
    |> Enum.reduce_while({:ok, %{}}, fn task, {:ok, task_definition_cache} ->
      case Map.get(task_definition_cache, task["taskDefinitionArn"]) do
        nil ->
          with {:ok, %{"taskDefinition" => task_definition}} <-
                 ExAws.ECS.describe_task_definition(task["taskDefinitionArn"])
                 |> ExAws.request(config) do
            {:cont, {:ok, Map.put(task_definition_cache, task["taskDefinitionArn"], task_definition)}}
          else
            error ->
              Logger.error("Error describing task definition: #{error}")
              {:halt, {:error, error}}
          end

        _ ->
          {:cont, {:ok, task_definition_cache}}
      end
    end)
  end

  # defp describe_container_instances(cluster, container_instances) do
  #   %{
  #     "Action" => "DescribeContainerInstances",
  #     "containerInstances" => container_instances,
  #     "cluster" => cluster
  #   }
  #   |> request()
  # end

  # defp request(%{"Action" => action} = params, opts \\ %{}) do
  #   params = Map.merge(params, %{"Version" => "2014-11-13"})

  #   ExAws.Operation.JSON.new(
  #     :ecs,
  #     %{
  #       data: params,
  #       headers: [
  #         {"x-amz-target", "AmazonEC2ContainerServiceV20141113.#{action}"},
  #         {"content-type", "application/x-amz-json-1.1"}
  #       ]
  #     }
  #     |> Map.merge(opts)
  #   )
  # end
end
