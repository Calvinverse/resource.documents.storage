# frozen_string_literal: true

#
# Cookbook Name:: resource_documents_storage
# Recipe:: default
#
# Copyright 2018, P. van der Velde
#

# Always make sure that apt is up to date
apt_update 'update' do
  action :update
end

#
# Include the local recipes
#

include_recipe 'resource_documents_storage::firewall'

include_recipe 'resource_documents_storage::meta'

include_recipe 'resource_documents_storage::java'

include_recipe 'resource_documents_storage::elasticsearch'
include_recipe 'resource_documents_storage::elasticsearch_service'
include_recipe 'resource_documents_storage::elasticsearch_templates'

include_recipe 'resource_documents_storage::provisioning'
