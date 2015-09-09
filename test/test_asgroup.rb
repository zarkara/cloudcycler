require 'minitest/autorun'
require 'cloud/cycler/asgroup'
require 'cctest'

class MockAutoScalingInstance
  attr_reader :start_called, :stop_called, :terminate_called
  attr_reader :status
  attr_reader :instance_id

  def initialize(id)
    @instance_id = id
    @status      = :stopped
  end

  def ec2_instance
    self
  end

  def start
    @start_called = true
  end

  def stop
    @stop_called = true
  end

  def terminate
    @terminate_called = true
  end

  def exists?
    true
  end
end

class MockAWSAutoScaling
  def groups
    @groups ||= MockAutoScalingGroupCollection.new
  end
end

class MockAutoScalingGroupCollection
  def initialize
    @groups = Hash.new {|h,k| h[k] = MockAutoScalingGroup.new(k) }
  end

  def [](key)
    @groups[key]
  end
end

class MockAutoScalingGroup
  Processes = %w(Launch Terminate HealthCheck ReplaceUnhealthy AZRebalance AlarmNotification ScheduledActions AddToLoadBalancer)
  attr_accessor :suspended_processes

  def initialize(name, num = 1)
    @name                = name
    @num                 = num
    @suspended_processes = Processes
  end

  def exists?
    true
  end

  def auto_scaling_instances
    @auto_scaling_instances ||= @num.times.map do |n|
      MockAutoScalingInstance.new("#{@name}-#{n+1}")
    end
  end

  def suspend_all_processes
    @suspended_processes = Processes
  end

  def resume_all_processes
    @suspended_processes = []
  end
end

class TestASGroup < Minitest::Test
  def test_safe_start_stopped_group
    group = Cloud::Cycler::ASGroup.new(MockTask.new(false), 'as-12345')
    group.grace_period = 0

    aws_autoscaling = MockAWSAutoScaling.new

    group.stub(:aws_autoscaling, aws_autoscaling) do
      mock_group = aws_autoscaling.groups['as-12345']

      group.stub(:autoscaling_group, mock_group) do
        group.start
        assert(
          mock_group.auto_scaling_instances.none? {|x| x.start_called },
          'Autoscaling instances started'
        )
      end
    end
  end

  def test_safe_stop_started_group
    group = Cloud::Cycler::ASGroup.new(MockTask.new(false), 'as-12345')
    group.grace_period = 0

    aws_autoscaling = MockAWSAutoScaling.new

    group.stub(:aws_autoscaling, aws_autoscaling) do
      mock_group = aws_autoscaling.groups['as-12345']
      mock_group.suspended_processes = []

      group.stub(:autoscaling_group, mock_group) do
        group.stop(:stop)
        assert(mock_group.auto_scaling_instances.none? {|x| x.stop_called })
      end
    end
  end

  def test_safe_terminate_started_group
    group = Cloud::Cycler::ASGroup.new(MockTask.new(false), 'as-12345')
    group.grace_period = 0

    aws_autoscaling = MockAWSAutoScaling.new

    group.stub(:aws_autoscaling, aws_autoscaling) do
      mock_group = aws_autoscaling.groups['as-12345']
      mock_group.suspended_processes = []

      group.stub(:autoscaling_group, mock_group) do
        group.stop(:terminate)
        assert(mock_group.auto_scaling_instances.none? {|x| x.terminate_called })
      end
    end
  end

  def test_unsafe_start_stopped_group
    group = Cloud::Cycler::ASGroup.new(MockTask.new(true), 'as-12345')
    group.grace_period = 0

    aws_autoscaling = MockAWSAutoScaling.new

    group.stub(:aws_autoscaling, aws_autoscaling) do
      mock_group = aws_autoscaling.groups['as-12345']

      group.stub(:autoscaling_group, mock_group) do
        group.start
        assert(
          mock_group.suspended_processes.empty?,
          'Autoscaling group processes not resumed'
        )
        assert(
          mock_group.auto_scaling_instances.all? {|x| x.start_called },
          'Autoscaling instances not started'
        )
      end
    end
  end

  def test_unsafe_start_terminated_group
    group = Cloud::Cycler::ASGroup.new(MockTask.new(true), 'as-12345')
    group.grace_period = 0

    aws_autoscaling = MockAWSAutoScaling.new

    group.stub(:aws_autoscaling, aws_autoscaling) do
      mock_group = aws_autoscaling.groups['as-12345']

      group.stub(:autoscaling_group, mock_group) do
        group.start
        assert(
          mock_group.suspended_processes.empty?,
          'Autoscaling group processes not resumed'
        )
      end
    end
  end

  def test_unsafe_stop_started_group
    group = Cloud::Cycler::ASGroup.new(MockTask.new(true), 'as-12345')
    group.grace_period = 0

    aws_autoscaling = MockAWSAutoScaling.new

    group.stub(:aws_autoscaling, aws_autoscaling) do
      mock_group = aws_autoscaling.groups['as-12345']
      mock_group.suspended_processes = []

      group.stub(:autoscaling_group, mock_group) do
        group.stop(:stop)
        assert(
          mock_group.auto_scaling_instances.all? {|x| x.stop_called },
          'Autoscaling instances not stopped'
        )
      end
    end
  end

  def test_unsafe_terminate_started_group
    group = Cloud::Cycler::ASGroup.new(MockTask.new(true), 'as-12345')
    group.grace_period = 0

    aws_autoscaling = MockAWSAutoScaling.new

    group.stub(:aws_autoscaling, aws_autoscaling) do
      mock_group = aws_autoscaling.groups['as-12345']
      mock_group.suspended_processes = []

      group.stub(:autoscaling_group, mock_group) do
        group.stop(:terminate)
        assert(
          mock_group.auto_scaling_instances.all? {|x| x.terminate_called },
          'Autoscaling instances not terminated'
        )
      end
    end
  end
end
