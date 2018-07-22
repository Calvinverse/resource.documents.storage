# frozen_string_literal: true

#
# Cookbook Name:: resource_documents_storage
# Recipe:: elasticsearch
#
# Copyright 2017, P. van der Velde
#

es_user = node['elasticsearch']['service_user']
es_group = node['elasticsearch']['service_group']
poise_service_user es_user do
  group es_group
end

#
# CREATE DATA PATH
#

service_path = node['elasticsearch']['path']['data_base']
directory service_path do
  action :create
  recursive true
end

elasticsearch_data_path = node['elasticsearch']['path']['data']
directory elasticsearch_data_path do
  action :create
  group node['elasticsearch']['service_group']
  mode '775'
  owner node['elasticsearch']['service_user']
  recursive true
end

#
# INSTALL ELASTICSEARCH
#

elasticsearch_install 'elasticsearch-install' do
  action :install
  type 'repository'
  version '6.2.4'
end

#
# SERVICE
#

# Create the systemd service for consultemplate.
service_name = 'elasticsearch'
environment_values = {
  'ES_HOME' => node['elasticsearch']['path']['home'],
  'ES_PATH_CONF' => node['elasticsearch']['path']['config'],
  'PID_DIR' => node['elasticsearch']['path']['pid']
}
systemd_service service_name do
  action :create
  install do
    wanted_by %w[network-online.target]
  end
  service do
    environment environment_values
    exec_start "#{node['elasticsearch']['path']['home']}/bin/elasticsearch -p #{node['elasticsearch']['path']['pid']}/elasticsearch.pid"
    group node['elasticsearch']['service_group']
    kill_mode 'process'
    kill_signal 'SIGTERM'
    limit_as 'infinity'
    limit_nofile 65_536
    limit_nproc 4096
    restart 'on-failure'
    runtime_directory 'elasticsearch'
    send_sigkill false
    success_exit_status 143
    timeout_stop_sec 0
    user node['elasticsearch']['service_user']
    working_directory node['elasticsearch']['path']['home']
  end
  unit do
    after %w[network-online.target]
    description 'Elasticsearch'
    requires %w[multi-user.target]
    wants %w[network-online.target]
  end
end

service service_name do
  action :enable
end

#
# ALLOW ELASTICSEARCH THROUGH THE FIREWALL
#

http_port = node['elasticsearch']['port']['http']
firewall_rule 'elasticsearch-http' do
  command :allow
  description 'Allow ElasticSearch HTTP traffic'
  dest_port http_port
  direction :in
end

#
# CONSUL FILES
#

file '/etc/consul/conf.d/elasticsearch-http.json' do
  action :create
  content <<~JSON
    {
      "services": [
        {
          "checks": [
            {
              "http": "http://localhost:#{http_port}/ping",
              "id": "elasticsearch_http_health_check",
              "interval": "30s",
              "method": "GET",
              "name": "ElasticSearch HTTP health check",
              "timeout": "5s"
            }
          ],
          "enableTagOverride": false,
          "id": "elasticsearch_http",
          "name": "documents",
          "port": #{http_port},
          "tags": [
            "http"
          ]
        }
      ]
    }
  JSON
end

#
# CONSUL-TEMPLATE FILES
#

consul_template_config_path = node['consul_template']['config_path']
consul_template_template_path = node['consul_template']['template_path']

# config file

telegraf_service = 'telegraf'
telegraf_config_directory = node['telegraf']['config_directory']
telegraf_elasticsearch_inputs_template_file = node['elasticsearch']['telegraf']['consul_template_inputs_file']
file "#{consul_template_template_path}/#{telegraf_elasticsearch_inputs_template_file}" do
  action :create
  content <<~CONF
    # Telegraf Configuration

    ###############################################################################
    #                            INPUT PLUGINS                                    #
    ###############################################################################

    [[inputs.elasticsearch]]
    ## specify a list of one or more Elasticsearch servers
    servers = ["http://localhost:#{http_port}"]

    ## Timeout for HTTP requests to the elastic search server(s)
    http_timeout = "5s"

    ## When local is true (the default), the node will read only its own stats.
    ## Set local to false when you want to read the node stats from all nodes
    ## of the cluster.
    local = true

    ## Set cluster_health to true when you want to also obtain cluster health stats
    cluster_health = false

    ## Adjust cluster_health_level when you want to also obtain detailed health stats
    ## The options are
    ##  - indices (default)
    ##  - cluster
    # cluster_health_level = "indices"

    ## Set cluster_stats to true when you want to also obtain cluster stats from the
    ## Master node.
    cluster_stats = false

    ## node_stats is a list of sub-stats that you want to have gathered. Valid options
    ## are "indices", "os", "process", "jvm", "thread_pool", "fs", "transport", "http",
    ## "breaker". Per default, all stats are gathered.
    # node_stats = ["jvm", "http"]

    ## Optional SSL Config
    # ssl_ca = "/etc/telegraf/ca.pem"
    # ssl_cert = "/etc/telegraf/cert.pem"
    # ssl_key = "/etc/telegraf/key.pem"
    ## Use SSL but skip chain & host verification
    # insecure_skip_verify = false
    [inputs.elasticsearch.tags]
      influxdb_database = "{{ keyOrDefault "config/services/metrics/databases/services" "services" }}"
  CONF
  mode '755'
end

file "#{consul_template_config_path}/telegraf_elasticsearch_inputs.hcl" do
  action :create
  content <<~HCL
    # This block defines the configuration for a template. Unlike other blocks,
    # this block may be specified multiple times to configure multiple templates.
    # It is also possible to configure templates via the CLI directly.
    template {
      # This is the source file on disk to use as the input template. This is often
      # called the "Consul Template template". This option is required if not using
      # the `contents` option.
      source = "#{consul_template_template_path}/#{telegraf_elasticsearch_inputs_template_file}"

      # This is the destination path on disk where the source template will render.
      # If the parent directories do not exist, Consul Template will attempt to
      # create them, unless create_dest_dirs is false.
      destination = "#{telegraf_config_directory}/inputs_elasticsearch.conf"

      # This options tells Consul Template to create the parent directories of the
      # destination path if they do not exist. The default value is true.
      create_dest_dirs = false

      # This is the optional command to run when the template is rendered. The
      # command will only run if the resulting template changes. The command must
      # return within 30s (configurable), and it must have a successful exit code.
      # Consul Template is not a replacement for a process monitor or init system.
      command = "systemctl reload #{telegraf_service}"

      # This is the maximum amount of time to wait for the optional command to
      # return. Default is 30s.
      command_timeout = "15s"

      # Exit with an error when accessing a struct or map field/key that does not
      # exist. The default behavior will print "<no value>" when accessing a field
      # that does not exist. It is highly recommended you set this to "true" when
      # retrieving secrets from Vault.
      error_on_missing_key = false

      # This is the permission to render the file. If this option is left
      # unspecified, Consul Template will attempt to match the permissions of the
      # file that already exists at the destination path. If no file exists at that
      # path, the permissions are 0644.
      perms = 0755

      # This option backs up the previously rendered template at the destination
      # path before writing a new one. It keeps exactly one backup. This option is
      # useful for preventing accidental changes to the data without having a
      # rollback strategy.
      backup = true

      # These are the delimiters to use in the template. The default is "{{" and
      # "}}", but for some templates, it may be easier to use a different delimiter
      # that does not conflict with the output file itself.
      left_delimiter  = "{{"
      right_delimiter = "}}"

      # This is the `minimum(:maximum)` to wait before rendering a new template to
      # disk and triggering a command, separated by a colon (`:`). If the optional
      # maximum value is omitted, it is assumed to be 4x the required minimum value.
      # This is a numeric time with a unit suffix ("5s"). There is no default value.
      # The wait value for a template takes precedence over any globally-configured
      # wait.
      wait {
        min = "2s"
        max = "10s"
      }
    }
  HCL
  mode '755'
end
