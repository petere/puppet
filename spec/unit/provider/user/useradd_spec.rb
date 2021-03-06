#! /usr/bin/env ruby -S rspec
require 'spec_helper'

describe Puppet::Type.type(:user).provider(:useradd) do

  before :each do
    described_class.stubs(:command).with(:password).returns '/usr/bin/chage'
    described_class.stubs(:command).with(:add).returns '/usr/sbin/useradd'
    described_class.stubs(:command).with(:modify).returns '/usr/sbin/usermod'
    described_class.stubs(:command).with(:delete).returns '/usr/sbin/userdel'
  end

  let(:resource) do
    Puppet::Type.type(:user).new(
      :name       => 'myuser',
      :managehome => :false,
      :system     => :false,
      :provider   => provider
    )
  end

  let(:provider) { described_class.new(:name => 'myuser') }

  describe "#create" do

    it "should add -o when allowdupe is enabled and the user is being created" do
      resource[:allowdupe] = true
      provider.expects(:execute).with(['/usr/sbin/useradd', '-o', 'myuser'])
      provider.create
    end

    describe "on systems that support has_system", :if => described_class.system_users? do
      it "should add -r when system is enabled" do
        resource[:system] = :true
        provider.should be_system_users
        provider.expects(:execute).with(['/usr/sbin/useradd', '-r', 'myuser'])
        provider.create
      end
    end

    describe "on systems that do not support has_system", :unless => described_class.system_users? do
      it "should not add -r when system is enabled" do
        resource[:system] = :true
        provider.should_not be_system_users
        provider.expects(:execute).with(['/usr/sbin/useradd', 'myuser'])
        provider.create
      end
    end

    it "should set password age rules" do
      described_class.has_feature :manages_password_age
      resource[:password_min_age] = 5
      resource[:password_max_age] = 10
      provider.expects(:execute).with(['/usr/sbin/useradd', 'myuser'])
      provider.expects(:execute).with(['/usr/bin/chage', '-m', 5, '-M', 10, 'myuser'])
      provider.create
    end
  end

  describe "#uid=" do
    it "should add -o when allowdupe is enabled and the uid is being modified" do
      resource[:allowdupe] = :true
      provider.expects(:execute).with(['/usr/sbin/usermod', '-u', 150, '-o', 'myuser'])
      provider.uid = 150
    end
  end

  describe "#check_allow_dup" do
    it "should check allow dup" do
      resource.expects(:allowdupe?)
      provider.check_allow_dup
    end

    it "should return an array with a flag if dup is allowed" do
      resource[:allowdupe] = :true
      provider.check_allow_dup.must == ["-o"]
    end

    it "should return an empty array if no dup is allowed" do
      resource[:allowdupe] = :false
      provider.check_allow_dup.must == []
    end
  end

  describe "#check_system_users" do
    it "should check system users" do
      described_class.expects(:system_users?).returns true
      resource.expects(:system?)
      provider.check_system_users
    end

    it "should return an array with a flag if it's a system user" do
      described_class.expects(:system_users?).returns true
      resource[:system] = :true
      provider.check_system_users.must == ["-r"]
    end

    it "should return an empty array if it's not a system user" do
      described_class.expects(:system_users?).returns true
      resource[:system] = :false
      provider.check_system_users.must == []
    end

    it "should return an empty array if system user is not featured" do
      described_class.expects(:system_users?).returns false
      resource[:system] = :true
      provider.check_system_users.must == []
    end
  end

  describe "#check_manage_home" do
    it "should check manage home" do
      resource.expects(:managehome?)
      provider.check_manage_home
    end

    it "should return an array with -m flag if home is managed" do
      resource[:managehome] = :true
      provider.check_manage_home.must == ["-m"]
    end

    it "should return an array with -r flag if home is managed" do
      resource[:managehome] = :true
      resource[:ensure] = :absent
      provider.deletecmd.must == ['/usr/sbin/userdel', '-r', 'myuser']
    end

    it "should return an array with -M if home is not managed and on Redhat" do
      Facter.stubs(:value).with(:operatingsystem).returns("RedHat")
      resource[:managehome] = :false
      provider.check_manage_home.must == ["-M"]
    end

    it "should return an empty array if home is not managed and not on Redhat" do
      Facter.stubs(:value).with(:operatingsystem).returns("some OS")
      resource[:managehome] = :false
      provider.check_manage_home.must == []
    end
  end

  describe "when adding properties" do
    it "should get the valid properties"
    it "should not add the ensure property"
    it "should add the flag and value to an array"
    it "should return and array of flags and values"
  end

  describe "#addcmd" do
    before do
      resource[:allowdupe] = :true
      resource[:managehome] = :true
      resource[:system] = :true
    end

    it "should call command with :add" do
      provider.expects(:command).with(:add)
      provider.addcmd
    end

    it "should add properties" do
      provider.expects(:add_properties).returns(['-foo_add_properties'])
      provider.addcmd.should include '-foo_add_properties'
    end

    it "should check and add if dup allowed" do
      provider.expects(:check_allow_dup).returns(['-allow_dup_flag'])
      provider.addcmd.should include '-allow_dup_flag'
    end

    it "should check and add if home is managed" do
      provider.expects(:check_manage_home).returns(['-manage_home_flag'])
      provider.addcmd.should include '-manage_home_flag'
    end

    it "should add the resource :name" do
      provider.addcmd.should include 'myuser'
    end

    describe "on systems featuring system_users", :if => described_class.system_users? do
      it "should return an array with -r if system? is true" do
        resource[:system] = :true
        provider.addcmd.should include("-r")
      end

      it "should return an array without -r if system? is false" do
        resource[:system] = :false
        provider.addcmd.should_not include("-r")
      end
    end

    describe "on systems not featuring system_users", :unless => described_class.system_users? do
      [:false, :true].each do |system|
        it "should return an array without -r if system? is #{system}" do
          resource[:system] = system
          provider.addcmd.should_not include("-r")
        end
      end
    end

    it "should return an array with full command" do
      described_class.expects(:system_users?).returns true
      provider.stubs(:add_properties).returns(["-G", "somegroup"])
      resource[:expiry] = "2012-08-18"

      provider.addcmd.must == ["/usr/sbin/useradd", "-G", "somegroup", "-o", "-m", '-e 2012-08-18', "-r", "myuser"]
    end

    it "should return an array without -e if expiry is undefined full command" do
      described_class.expects(:system_users?).returns true
      provider.stubs(:add_properties).returns(["-G", "somegroup"])
      provider.addcmd.must == ["/usr/sbin/useradd", "-G", "somegroup", "-o", "-m", "-r", "myuser"]
    end
  end

  describe "#passcmd" do
    before do
      resource[:allowdupe] = :true
      resource[:managehome] = :true
      resource[:system] = :true
    end

    it "should call command with :pass" do
      # command(:password) is only called inside passcmd if
      # password_min_age or password_max_age is set
      resource[:password_min_age] = 123
      provider.expects(:command).with(:password)
      provider.passcmd
    end

    it "should return nil if neither min nor max is set" do
      provider.passcmd.must be_nil
    end

    it "should return a chage command array with -m <value> and the user name if password_min_age is set" do
      resource[:password_min_age] = 123
      provider.passcmd.must == ['/usr/bin/chage','-m',123,'myuser']
    end

    it "should return a chage command array with -M <value> if password_max_age is set" do
      resource[:password_max_age] = 999
      provider.passcmd.must == ['/usr/bin/chage','-M',999,'myuser']
    end

    it "should return a chage command array with -M <value> -m <value> if both password_min_age and password_max_age are set" do
      resource[:password_min_age] = 123
      resource[:password_max_age] = 999
      provider.passcmd.must == ['/usr/bin/chage','-m',123,'-M',999,'myuser']
    end
  end
end
