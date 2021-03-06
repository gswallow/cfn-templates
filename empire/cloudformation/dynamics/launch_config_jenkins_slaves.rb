SparkleFormation.dynamic(:launch_config_jenkins_slaves) do |_name, _config = {}|

  # either _config[:volume_count] or _config[:snapshots] must be set
  # to generate a template with EBS device mappings.

  # {
  #   "Type" : "AWS::AutoScaling::LaunchConfiguration",
  #   "Properties" : {
  #     "AssociatePublicIpAddress" : Boolean,
  #     "BlockDeviceMappings" : [ BlockDeviceMapping, ... ],
  #     "EbsOptimized" : Boolean,
  #     "IamInstanceProfile" : String,
  #     "ImageId" : String,
  #     "InstanceId" : String,
  #     "InstanceMonitoring" : Boolean,
  #     "InstanceType" : String,
  #     "KernelId" : String,
  #     "KeyName" : String,
  #     "RamDiskId" : String,
  #     "SecurityGroups" : [ SecurityGroup, ... ],
  #     "SpotPrice" : String,
  #     "UserData" : String
  #   }
  # }

  _config[:ami_map] ||= :region_to_jenkins_slave_ami
  _config[:iam_instance_profile] ||= :jenkinsslaves_iam_instance_profile
  _config[:iam_instance_role] ||= :jenkinsslaves_iam_instance_role
  _config[:bootstrap_files] ||= :default_bootstrap_files
  _config[:extra_bootstrap] ||= nil # a registry, if defined.  Make sure to add newlines as '\n'.
  _config[:cluster] ||= :default_ecs_cluster

  parameters("#{_name}_instance_type".to_sym) do
    type 'String'
    allowed_values %w(t2.micro  t2.small   t2.medium  t2.large t2.xlarge t2.2xlarge
                      m3.medium m3.large   m3.xlarge  m3.2xlarge
                      m4.large  m4.xlarge  m4.2xlarge m4.4xlarge m4.10xlarge
                      c3.large  c3.xlarge  c3.2xlarge c3.4xlarge c3.8xlarge
                      c4.large  c4.xlarge  c4.2xlarge c4.4xlarge c4.8xlarge
                      r3.large  r3.xlarge  r3.2xlarge r3.4xlarge r3.8xlarge
                      r4.large  r4.xlarge  r4.2xlarge r4.4xlarge r4.8xlarge
                      i2.xlarge i2.2xlarge i2.4xlarge i2.8xlarge
                      ).sort
    default _config[:instance_type] || 'm3.medium'
  end

  parameters("#{_name}_instance_monitoring".to_sym) do
    type 'String'
    allowed_values %w(true false)
    default _config.fetch(:monitoring, 'false').to_s
    description 'Enable detailed cloudwatch monitoring for each instance'
  end

  parameters("#{_name}_associate_public_ip_address".to_sym)do
    type 'String'
    allowed_values %w(true false)
    default _config.fetch(:public_ips, 'true').to_s
    description 'Associate public IP addresses to instances'
  end

  parameters(:root_volume_size) do
    type 'Number'
    min_value '1'
    max_value '1000'
    default _config[:root_volume_size] || '12'
    description 'The size of the root volume (/dev/sda1) in gigabytes'
  end

  if _config.fetch(:create_ebs_volume, false)
    conditions.set!(
        "#{_name}_volumes_are_io1".to_sym,
        equals!(ref!("#{_name}_ebs_volume_type".to_sym), 'io1')
    )

    parameters("#{_name}_ebs_volume_size".to_sym) do
      type 'Number'
      min_value '1'
      max_value '1000'
      default _config[:volume_size] || '100'
    end

    parameters("#{_name}_ebs_volume_type".to_sym) do
      type 'String'
      allowed_values _array('standard', 'gp2', 'io1')
      default _config[:volume_type] || 'gp2'
      description 'Magnetic (standard), General Purpose (gp2), or Provisioned IOPS (io1)'
    end

    parameters("#{_name}_ebs_provisioned_iops".to_sym) do
      type 'Number'
      min_value '1'
      max_value '4000'
      default _config[:piops] || '300'
    end

    parameters("#{_name}_delete_ebs_volume_on_termination".to_sym) do
      type 'String'
      allowed_values ['true', 'false']
      default _config[:del_on_term] || 'true'
    end

    parameters("#{_name}_instances_ebs_optimized".to_sym) do
      type 'String'
      allowed_values _array('true', 'false')
      default _config[:ebs_optimized] || 'false'
      description 'Create an EBS-optimized instance (additional charges apply)'
    end
  end

  if _config.fetch(:create_ebs_swap, false)
    parameters("#{_name}_ebs_swap_size".to_sym) do
      type 'Number'
      min_value '1'
      max_value '100'
      default _config[:swap_size] || '8'
    end
  end

  parameters("#{_name}_spot_price".to_sym) do
    type 'Number'
    min_value '0.001'
    max_value '1.000'
    default _config[:spot_price] || '0.075'
  end

  resources("#{_name}_launch_config".to_sym) do
    type 'AWS::AutoScaling::LaunchConfiguration'
    registry!(_config[:bootstrap_files])
    properties do
      image_id map!(_config[:ami_map], ref!('AWS::Region'), :ami)
      instance_type ref!("#{_name}_instance_type".to_sym)
      instance_monitoring ref!("#{_name}_instance_monitoring".to_sym)
      iam_instance_profile ref!(_config[:iam_instance_profile])
      associate_public_ip_address ref!("#{_name}_associate_public_ip_address".to_sym)
      key_name ref!(:ssh_key_pair)

      security_groups _config[:security_groups]

      if _config.fetch(:create_ebs_volume, false)
        ebs_optimized ref!("#{_name}_instances_ebs_optimized".to_sym)
      end

      bdm = [
        -> {
          device_name '/dev/sda1'
          ebs do
            delete_on_termination 'true'
            volume_type 'gp2'
            volume_size ref!(:root_volume_size)
          end
        }
      ]

      if _config.fetch(:create_ebs_swap, false)
        bdm.push(
          -> {
            device_name '/dev/sdi'
            ebs do
              volume_type 'gp2'
              volume_size ref!("#{_name}_ebs_swap_size".to_sym)
            end
          }
        )
      end

      if _config.fetch(:create_ebs_volume, false)
        bdm.push(
          -> {
            device_name '/dev/sdh'
            ebs do
              iops if!("#{_name}_volumes_are_io1".to_sym, ref!("#{_name}_ebs_provisioned_iops".to_sym), no_value!)
              delete_on_termination ref!("#{_name}_delete_ebs_volume_on_termination".to_sym)
              volume_type ref!("#{_name}_ebs_volume_type".to_sym)
              volume_size ref!("#{_name}_ebs_volume_size".to_sym)
            end
          }
        )
      end

      block_device_mappings _array(
        *bdm
      )

      spot_price ref!("#{_name}_spot_price".to_sym)

      user_data base64!(
        join!(
          "#!/bin/bash\n",
          "# I would like to move the ansible startup to user-data.\n\n",

          "# We are using resource signaling, rather than wait condition handles\n",
          "# http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-signal.html\n\n",

          "function my_instance_id\n",
          "{\n",
          "  curl -sL http://169.254.169.254/latest/meta-data/instance-id/\n",
          "}\n\n",

          "function cfn_signal_and_exit\n",
          "{\n",
          "  status=$?\n",
          "  if [ $status -eq 0 ]; then\n",
          "    /usr/local/bin/cfn-signal ",
          " --role ", ref!(_config[:iam_instance_role]),
          " --region ", ref!('AWS::Region'),
          " --resource ", "#{_name.capitalize}Asg",
          " --stack ", ref!('AWS::StackName'),
          " --exit-code $status\n",
          "  else\n",
          "    sleep 180\n", # Crude, yes.  Give me 10 minutes to explore.
          "    /usr/local/bin/aws autoscaling set-instance-health --instance-id $(my_instance_id) --health-status Unhealthy --region ", ref!('AWS::Region'), "\n",
          "  fi\n",
          "  exit $status\n",
          "}\n\n",

          "apt-get update\n\n",

          "# Install the cloudformation helper scripts\n",
          "apt-get -y install python-setuptools python-pip python-lockfile unzip\n",
          "apt-get -y install --reinstall ca-certificates\n",
          "pip install --timeout=60 s3cmd\n",
          "easy_install https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.tar.gz\n\n",

          "# Install the AWS Command Line Interface\n",
          "curl -sL https://s3.amazonaws.com/aws-cli/awscli-bundle.zip -o /tmp/awscli-bundle.zip\n",
          "unzip -d /tmp /tmp/awscli-bundle.zip\n",
          "/tmp/awscli-bundle/install -i /opt/aws -b /usr/local/bin/aws\n",
          "rm -rf /tmp/awscli-bundle*\n\n",

          "# Grab an ansible seed file.\n",
          "/usr/local/bin/cfn-init -s ", ref!("AWS::StackName"), " --resource ", "#{_name.capitalize}LaunchConfig",
          "   --region ", ref!("AWS::Region"), " || cfn_signal_and_exit\n\n",

          "# Run ansible.\n",
          "env $(cat /etc/jenkins-slave/seed) ansible-playbook -c local /etc/jenkins-slave/site.yml\n",
          "cfn_signal_and_exit\n"
        )
      )
    end
  end
end
