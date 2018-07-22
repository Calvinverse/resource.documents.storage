# frozen_string_literal: true

#
# Cookbook Name:: resource_documents_storage
# Recipe:: provisioning
#
# Copyright 2018, P. van der Velde
#

service 'provision.service' do
  action [:enable]
end
