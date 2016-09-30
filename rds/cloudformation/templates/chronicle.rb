require 'sparkle_formation'
require_relative '../../../utils/environment'
require_relative '../../../utils/lookup'

ENV['net_type']             ||= 'Public'
ENV['public_sg']            ||= 'chronicle_sg'
ENV['private_sg']           ||= 'private_sg,empire_sg'
ENV['restore_rds_snapshot'] ||= 'none'

lookup = Indigo::CFN::Lookups.new
vpc = lookup.get_vpc

snapshot = ENV['restore_rds_snapshot'] == 'none' ? false : lookup.get_latest_rds_snapshot(ENV['restore_rds_snapshot'])

SparkleFormation.new('chronicle').load(:engine_versions, :force_ssl).overrides do
  set!('AWSTemplateFormatVersion', '2010-09-09')
  description <<EOF
Creates an RDS instance, running the postgresql engine.  Ties the RDS instance into a VPC's private subnets.
EOF

  dynamic!(:db_subnet_group, 'chronicle', :subnets => lookup.get_private_subnet_ids(vpc))
  dynamic!(:db_security_group, 'chronicle', :vpc => vpc, :security_group => lookup.get_security_group_ids(vpc, ENV['private_sg']))

  dynamic!(:rds_db_instance,
           'chronicle',
           :engine => 'postgres',
           :db_subnet_group => :chronicle_db_subnet_group,
           :db_security_groups => [ 'ChronicleDbSecurityGroup' ],
           :db_parameter_group => 'RdsForceSsl')

  dynamic!(:route53_record_set, 'chronicle',
           :record => 'chronicle-rds',
           :target => :chronicle_rds_db_instance,
           :domain_name => ENV['private_domain'],
           :attr => 'Endpoint.Address',
           :ttl => '60')

  dynamic!(:db_subnet_group, 'chroniclereadonly', :subnets => lookup.get_public_subnet_ids(vpc))

  dynamic!(:readonly_rds_db_instance,
           'chroniclereadonly',
           :engine => 'postgres',
           :db_subnet_group => :chroniclereadonly_db_subnet_group,
           :vpc_security_groups => lookup.get_security_group_ids(vpc, ENV['public_sg']),
           :source_db_instance_identifier => ref!('ChronicleRdsDbInstance')
           )


  dynamic!(:route53_record_set, 'chronicle',
           :record => 'chronicle',
           :target => :chroniclereadonly_rds_db_instance,
           :domain_name => ENV['public_domain'],
           :attr => 'Endpoint.Address',
           :ttl => '60')
end
