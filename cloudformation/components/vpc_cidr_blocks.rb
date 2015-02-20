SparkleFormation.build do
  ENV['region'] ||= 'us-east-1'
  cidrs = { 'us-east-1'    => { 'network' => '20', 'azs' => ['a', 'c', 'd', 'e'] },
            'us-west-1'    => { 'network' => '22', 'azs' => ['a', 'b', 'c'] },
            'us-west-2'    => { 'network' => '24', 'azs' => ['a', 'b', 'c'] },
            'eu-west-1'    => { 'network' => '26', 'azs' => ['a', 'b', 'c'] },
            'eu-central-1' => { 'network' => '28', 'azs' => ['a', 'b'] }
          }

  mappings(:cidr_to_region) do
    _camel_keys_set(:auto_disable)
    cidrs.each do |region, data|
      set!("#{region}", :cidr => "172.#{data['network']}.0.0/16")
    end
  end

  mappings(:subnets_to_az) do
    _camel_keys_set(:auto_disable)
    cidrs[ENV['region']]['azs'].each_with_index do |az, i|
      set!("#{ENV['region']}#{az}",
           :public => "172.#{cidrs[ENV['region']]['network']}.#{i * 16}.0/20",
           :private => "172.#{cidrs[ENV['region']]['network']}.#{240 - i * 16}.0/20")
    end
  end
end
