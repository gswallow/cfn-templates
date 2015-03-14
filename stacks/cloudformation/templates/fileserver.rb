require 'fog'
require 'sparkle_formation'

ENV['org'] ||= 'indigo'
ENV['environment'] ||= 'dr'
ENV['region'] ||= 'us-east-1'
pfx = "#{ENV['org']}-#{ENV['environment']}-#{ENV['region']}"

ENV['vpc'] ||= "#{pfx}-vpc"
ENV['net_type'] ||= 'Private'
ENV['sg'] ||= 'private_sg'

# Find subnets and security groups by VPC membership and network type.  These subnets
# and security groups will be passed into the ASG and launch config (respectively) so
# that the ASG knows where to launch instances.

def extract(response)
  response.body if response.status == 200
end

connection = Fog::Compute.new({ :provider => 'AWS', :region => ENV['region'] })

vpcs = extract(connection.describe_vpcs)['vpcSet']
vpc = vpcs.find { |vpc| vpc['tagSet'].fetch('Name', nil) == ENV['vpc']}['vpcId']

subnets = extract(connection.describe_subnets)['subnetSet']
subnets.collect! { |sn| sn['subnetId'] if sn['tagSet'].fetch('Network', nil) == ENV['net_type'] and sn['vpcId'] == vpc }.compact!

sgs = Array.new
ENV['sg'].split(',').each do |sg|
  found_sgs = extract(connection.describe_security_groups)['securityGroupInfo']
  found_sgs.collect! { |fsg| fsg['groupId'] if fsg['tagSet'].fetch('Name', nil) == sg and fsg['vpcId'] == vpc }.compact!
  sgs.concat found_sgs
end

# TODO: You can automatically discover SNS topics.  I wonder if you can tag them?
sns = Fog::AWS::SNS.new
topics = extract(sns.list_topics)['Topics']
topic = topics.find { |e| e =~ /byebye/ }

# Build the template.

SparkleFormation.new('fileserver').load(:precise_ami, :ssh_key_pair, :chef_validator_key_bucket).overrides do
  set!('AWSTemplateFormatVersion', '2010-09-09')
  description <<EOF
Creates auto scaling groups containing fileserver instances, with a pair of EBS volumes to attach in a RAID-1
pair.  Each instance is given an IAM instance profile, which allows the instance to get objects from the Chef
Validator Key Bucket.

Launch this template while launching the databases.rb and rabbitmq templates.  Depends on the VPC template.
EOF

  dynamic!(:iam_instance_profile, 'default')

  dynamic!(:launch_config_chef_bootstrap, 'fileserver', :instance_type => 't2.small', :create_ebs_volumes => true, :volume_count => 2, :volume_size => 10, :security_groups => sgs, :chef_run_list => 'role[base],role[file_server]')
  dynamic!(:auto_scaling_group, 'fileserver', :launch_config => :fileserver_launch_config, :subnets => subnets, :notification_topic => topic)

end
