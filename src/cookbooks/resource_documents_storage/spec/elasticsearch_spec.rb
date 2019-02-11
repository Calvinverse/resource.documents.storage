# frozen_string_literal: true

require 'spec_helper'

describe 'resource_documents_storage::elasticsearch' do
  context 'installs Elastic Search' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates and mounts the data file system at /srv/elasticsearch' do
      expect(chef_run).to create_directory('/srv/elasticsearch')
    end

    it 'creates and mounts the meta file system at /srv/elasticsearch/data' do
      expect(chef_run).to create_directory('/srv/elasticsearch/data').with(
        group: 'elasticsearch',
        mode: '770',
        owner: 'elasticsearch'
      )
    end

    it 'creates the elasticsearch user' do
      expect(chef_run).to create_elasticsearch_user('elasticsearch')
    end

    it 'installs elasticsearch' do
      expect(chef_run).to install_elasticsearch('elasticsearch')
    end

    it 'configures elasticsearch' do
      expect(chef_run).to manage_elasticsearch_configure('elasticsearch')
    end

    elasticsearch_security_override_content = <<~PROPERTIES
      networkaddress.cache.ttl=0
      networkaddress.cache.negative.ttl=0
    PROPERTIES
    it 'creates the /etc/elasticsearch/java.security' do
      expect(chef_run).to create_file('/etc/elasticsearch/java.security')
        .with_content(elasticsearch_security_override_content)
    end

    elasticsearch_jvm_options_content = <<~PROPERTIES
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
      -Djava.security.properties=/etc/elasticsearch/java.security
    PROPERTIES
    it 'creates the /etc/elasticsearch/jvm.options' do
      expect(chef_run).to create_file('/etc/elasticsearch/jvm.options')
        .with_content(elasticsearch_jvm_options_content)
    end
  end

  context 'configures the firewall for ElasticSearch' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'opens the ElasticSearch HTTP port' do
      expect(chef_run).to create_firewall_rule('elasticsearch-http').with(
        command: :allow,
        dest_port: 9200,
        direction: :in
      )
    end
  end

  context 'registers the service with consul' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    consul_elasticsearch_http_config_content = <<~JSON
      {
        "services": [
          {
            "checks": [
              {
                "http": "http://localhost:9200/_cluster/health",
                "id": "elasticsearch_http_health_check",
                "interval": "30s",
                "method": "GET",
                "name": "ElasticSearch HTTP health check",
                "timeout": "5s"
              }
            ],
            "enable_tag_override": false,
            "id": "elasticsearch_http",
            "name": "documents",
            "port": 9200,
            "tags": [
              "http"
            ]
          }
        ]
      }
    JSON
    it 'creates the /etc/consul/conf.d/elasticsearch-http.json' do
      expect(chef_run).to create_file('/etc/consul/conf.d/elasticsearch-http.json')
        .with_content(consul_elasticsearch_http_config_content)
    end
  end
end
