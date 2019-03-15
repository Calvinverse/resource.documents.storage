# frozen_string_literal: true

#
# Cookbook Name:: resource_documents_storage
# Recipe:: provisioning
#
# Copyright 2018, P. van der Velde
#

file '/etc/init.d/provision_image.sh' do
  action :create
  content <<~BASH
    #!/bin/bash

    function f_provisionImage {
      sudo systemctl enable elasticsearch.service
    }
  BASH
  mode '755'
end

service 'provision.service' do
  action [:enable]
end
