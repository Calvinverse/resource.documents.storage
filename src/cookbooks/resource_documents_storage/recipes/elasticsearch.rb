# frozen_string_literal: true

#
# Cookbook Name:: resource_documents_storage
# Recipe:: elasticsearch
#
# Copyright 2017, P. van der Velde
#

#
# ELASTICSEARCH USER
#

es_user = node['elasticsearch']['service_user']
es_group = node['elasticsearch']['service_group']
elasticsearch_user 'elasticsearch' do
  action :create
  groupname es_group
  username es_user
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
  mode '770'
  owner node['elasticsearch']['service_user']
  recursive true
end

#
# INSTALL ELASTICSEARCH
#

elasticsearch_install 'elasticsearch' do
  action :install
  type 'repository'
  version node['elasticsearch']['version']
end

# install the service. We'll overwrite that but we need this here in order
# to write all the configurations
service_name = node['elasticsearch']['service_name']
elasticsearch_service service_name do
  action :nothing
end

#
# CONFIGURATION
#

elasticsearch_config_path = node['elasticsearch']['path']['config']
elasticsearch_data_path = node['elasticsearch']['path']['data']
elasticsearch_log_path = node['elasticsearch']['path']['logs']

elasticsearch_configure 'elasticsearch' do
  action :manage
  logging(action: 'INFO')
  path_bin node['elasticsearch']['path']['bin']
  path_conf elasticsearch_config_path
  path_data elasticsearch_data_path
  path_home node['elasticsearch']['path']['home']
  path_logs elasticsearch_log_path
  path_pid node['elasticsearch']['path']['pid']
  path_plugins node['elasticsearch']['path']['plugins']
end

# Disable DNS caching in the JVM. We have unbound for this. See:
# - https://docs.oracle.com/javase/8/docs/technotes/guides/net/properties.html
# - https://github.com/elastic/elasticsearch/issues/16412
elasticsearch_jvm_security_override = "#{elasticsearch_config_path}/java.security"
file elasticsearch_jvm_security_override do
  action :create
  content <<~PROPERTIES
    networkaddress.cache.ttl=0
    networkaddress.cache.negative.ttl=0
  PROPERTIES
  group node['elasticsearch']['service_group']
  mode '0550'
  owner node['elasticsearch']['service_user']
end

file "#{elasticsearch_config_path}/jvm.options" do
  action :create
  content <<~CONF
    -XX:+UseConcMarkSweepGC
    -XX:CMSInitiatingOccupancyFraction=75
    -XX:+UseCMSInitiatingOccupancyOnly
    -XX:+AlwaysPreTouch
    -server
    -Xss1m
    -Djava.awt.headless=true
    -Dfile.encoding=UTF-8
    -Djna.nosys=true
    -XX:-OmitStackTraceInFastThrow
    -Dio.netty.noUnsafe=true
    -Dio.netty.noKeySetOptimization=true
    -Dio.netty.recycler.maxCapacityPerThread=0
    -Dlog4j.shutdownHookEnabled=false
    -Dlog4j2.disable.jmx=true
    -XX:+HeapDumpOnOutOfMemoryError
    -Djava.security.properties=#{elasticsearch_jvm_security_override}
  CONF
  group node['elasticsearch']['service_group']
  mode '0550'
  owner node['elasticsearch']['service_user']
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

discovery_port = node['elasticsearch']['port']['discovery']
firewall_rule 'elasticsearch-discovery' do
  command :allow
  description 'Allow ElasticSearch discovery traffic'
  dest_port discovery_port
  direction :in
end

#
# CONSUL FILES
#

consul_service_name = 'documents'
consul_service_tag = 'http'
file '/etc/consul/conf.d/elasticsearch-http.json' do
  action :create
  content <<~JSON
    {
      "services": [
        {
          "checks": [
            {
              "http": "http://localhost:#{http_port}/_cluster/health",
              "id": "elasticsearch_http_health_check",
              "interval": "30s",
              "method": "GET",
              "name": "ElasticSearch HTTP health check",
              "timeout": "5s"
            }
          ],
          "enable_tag_override": false,
          "id": "elasticsearch_http",
          "name": "#{consul_service_name}",
          "port": #{http_port},
          "tags": [
            "#{consul_service_tag}"
          ]
        }
      ]
    }
  JSON
end
