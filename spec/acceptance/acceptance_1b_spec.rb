require 'spec_helper_acceptance'

stop_test = (UNSUPPORTED_PLATFORMS.any?{ |up| fact('osfamily') == up} || SKIP_TOMCAT_8 || SKIP_GCC)

describe 'Acceptance case one', :unless => stop_test do
  after :all do
    shell('pkill -f tomcat', :acceptable_exit_codes => [0,1])
    shell('rm -rf /opt/tomcat*', :acceptable_exit_codes => [0,1])
    shell('rm -rf /opt/apache-tomcat*', :acceptable_exit_codes => [0,1])
  end

  context 'Initial install Tomcat and verification' do
    it 'Should apply the manifest without error' do
      pp = <<-EOS
      class{'java':}
      class{'gcc':}

      if $::operatingsystemmajrelease == '16.04' {
        $java_home = "/usr/lib/jvm/java-8-openjdk-${::architecture}"
      } else {
        $java_home = $::osfamily ? {
          'RedHat' => '/etc/alternatives/java_sdk',
          'Debian' => "/usr/lib/jvm/java-7-openjdk-${::architecture}",
          default  => undef
        }
      }

      class jsvc {
        archive { 'commons-daemon-native.tar.gz':
          extract      => true,
          cleanup      => false,
          path         => "/opt/apache-tomcat/bin/commons-daemon-native.tar.gz",
          extract_path => "/opt/apache-tomcat/bin",
          creates      => "/opt/apache-tomcat/bin/commons-daemon-#{LATEST_DAEMON}-native-src",
        }
        -> exec { 'configure jsvc':
          command  => "JAVA_HOME=${java_home} configure --with-java=${java_home}",
          creates  => "/opt/apache-tomcat/bin/commons-daemon-#{LATEST_DAEMON}-native-src/unix/Makefile",
          cwd      => "/opt/apache-tomcat/bin/commons-daemon-#{LATEST_DAEMON}-native-src/unix",
          path     => "/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin:/opt/apache-tomcat/bin/commons-daemon-#{LATEST_DAEMON}-native-src/unix",
          require  => [ Class['gcc'], Class['java'] ],
          provider => shell,
        }
        -> exec { 'make jsvc':
          command  => 'make',
          creates  => "/opt/apache-tomcat/bin/commons-daemon-#{LATEST_DAEMON}-native-src/unix/jsvc",
          cwd      => "/opt/apache-tomcat/bin/commons-daemon-#{LATEST_DAEMON}-native-src/unix",
          path     => "/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin:/opt/apache-tomcat/bin/commons-daemon-#{LATEST_DAEMON}-native-src/unix",
          provider => shell,
        }
        -> file { 'jsvc':
          ensure => link,
          path   => "/opt/apache-tomcat/bin/jsvc",
          target => "/opt/apache-tomcat/bin/commons-daemon-#{LATEST_DAEMON}-native-src/unix/jsvc",
        }
      }

      # The default
      tomcat::install { '/opt/apache-tomcat':
        user           => 'tomcat8',
        group          => 'tomcat8',
        source_url     => '#{TOMCAT8_RECENT_SOURCE}',
        allow_insecure => true,
      }
      -> class { 'jsvc': } ->
      tomcat::instance { 'tomcat_one':
        catalina_base => '/opt/apache-tomcat/tomcat8-jsvc',
        user          => 'tomcat8',
        group         => 'tomcat8',
        java_home     => $java_home,
        use_jsvc      => true,
      }
      tomcat::config::server { 'tomcat8-jsvc':
        catalina_base => '/opt/apache-tomcat/tomcat8-jsvc',
        port          => '80',
      }
      tomcat::config::server::connector { 'tomcat8-jsvc':
        catalina_base         => '/opt/apache-tomcat/tomcat8-jsvc',
        port                  => '80',
        protocol              => 'HTTP/1.1',
        additional_attributes => {
          'redirectPort' => '443'
        },
      }
      tomcat::config::server::connector { 'tomcat8-jsvc-8080':
        catalina_base         => '/opt/apache-tomcat/tomcat8-jsvc',
        port                  => '8080',
        protocol              => 'HTTP/1.1',
        additional_attributes => {
          'redirectPort' => '443'
        },
      }
      tomcat::config::server::connector { 'tomcat8-ajp':
        catalina_base         => '/opt/apache-tomcat/tomcat8-jsvc',
        connector_ensure      => absent,
        port                  => '8309',
      }
      tomcat::war { 'war_one.war':
        user  => 'tomcat8',
        group => 'tomcat8',
        catalina_base  => '/opt/apache-tomcat/tomcat8-jsvc',
        war_source     => '#{SAMPLE_WAR}',
        allow_insecure => true,
      }
      tomcat::setenv::entry { 'JAVA_HOME':
        user  => 'tomcat8',
        group => 'tomcat8',
        value => $java_home,
      }
      EOS
      apply_manifest(pp, :catch_failures => true)
      apply_manifest(pp, :catch_changes  => true)
    end
    it 'Should be serving a page on port 80', :retry => 5, :retry_wait => 10 do
      shell('curl localhost:80/war_one/hello.jsp', :acceptable_exit_codes => 0) do |r|
        r.stdout.should match(/Sample Application JSP Page/)
      end
    end
    it 'Should be serving a page on port 8080', :retry => 5, :retry_wait => 10 do
      shell('curl localhost:8080/war_one/hello.jsp', :acceptable_exit_codes => 0) do |r|
        r.stdout.should match(/Sample Application JSP Page/)
      end
    end
  end

  context 'Stop tomcat with verification!!!' do
    it 'Should apply the manifest without error' do
      pp = <<-EOS
      if $::operatingsystemmajrelease == '16.04' {
        $java_home = "/usr/lib/jvm/java-8-openjdk-${::architecture}"
      } else {
        $java_home = $::osfamily ? {
          'RedHat' => '/etc/alternatives/java_sdk',
          'Debian' => "/usr/lib/jvm/java-7-openjdk-${::architecture}",
          default  => undef
        }
      }

      tomcat::service { 'jsvc-default':
        service_ensure => stopped,
        catalina_home  => '/opt/apache-tomcat',
        catalina_base  => '/opt/apache-tomcat/tomcat8-jsvc',
        use_jsvc       => true,
        java_home      => $java_home,
        user           => 'tomcat8',
      }
      EOS
      apply_manifest(pp, :catch_failures => true, :acceptable_exit_codes => [0,2])
    end
    it 'Should not be serving a page on port 80', :retry => 5, :retry_wait => 10 do
      shell('curl localhost:80/war_one/hello.jsp', :acceptable_exit_codes => 7)
    end
  end

  context 'Start Tomcat with verification' do
    it 'Should apply the manifest without error' do
      pp = <<-EOS
      if $::operatingsystemmajrelease == '16.04' {
        $java_home = "/usr/lib/jvm/java-8-openjdk-${::architecture}"
      } else {
        $java_home = $::osfamily ? {
          'RedHat' => '/etc/alternatives/java_sdk',
          'Debian' => "/usr/lib/jvm/java-7-openjdk-${::architecture}",
          default  => undef
        }
      }

      tomcat::service { 'jsvc-default':
        service_ensure => running,
        catalina_home  => '/opt/apache-tomcat',
        catalina_base  => '/opt/apache-tomcat/tomcat8-jsvc',
        use_jsvc       => true,
        java_home      => $java_home,
        user           => 'tomcat8',
      }
      EOS
      apply_manifest(pp, :catch_failures => true, :acceptable_exit_codes => [0,2])
    end
    it 'Should be serving a page on port 80', :retry => 5, :retry_wait => 10 do
      shell('curl localhost:80/war_one/hello.jsp', :acceptable_exit_codes => 0) do |r|
        r.stdout.should match(/Sample Application JSP Page/)
      end
    end
  end

  context 'un-deploy the war with verification' do
    it 'Should apply the manifest without error' do
      pp = <<-EOS
      tomcat::war { 'war_one.war':
        catalina_base => '/opt/apache-tomcat/tomcat8-jsvc',
        war_source    => '#{SAMPLE_WAR}',
        war_ensure    => absent,
      }
      EOS
      apply_manifest(pp, :catch_failures => true, :acceptable_exit_codes => [0,2])
    end
    it 'Should not have deployed the war', :retry => 5, :retry_wait => 10 do
      shell('curl localhost:80/war_one/hello.jsp', :acceptable_exit_codes => 0) do |r|
        r.stdout.should eq("")
      end
    end
  end

  context 'remove the connector with verification' do

    it 'Should apply the manifest without error' do
      pp = <<-EOS
      if $::operatingsystemmajrelease == '16.04' {
        $java_home = "/usr/lib/jvm/java-8-openjdk-${::architecture}"
      } else {
        $java_home = $::osfamily ? {
          'RedHat' => '/etc/alternatives/java_sdk',
          'Debian' => "/usr/lib/jvm/java-7-openjdk-${::architecture}",
          default  => undef
        }
      }

      tomcat::config::server::connector { 'tomcat8-jsvc':
        connector_ensure => 'absent',
        catalina_base    => '/opt/apache-tomcat/tomcat8-jsvc',
        port             => '80',
        notify           => Tomcat::Service['jsvc-default']
      }
      tomcat::service { 'jsvc-default':
        service_ensure => running,
        catalina_home  => '/opt/apache-tomcat',
        catalina_base  => '/opt/apache-tomcat/tomcat8-jsvc',
        java_home      => $java_home,
        use_jsvc       => true,
        user           => 'tomcat8',
      }
      EOS
      apply_manifest(pp, :catch_failures => true, :acceptable_exit_codes => [0,2])
    end
    it 'Should not be able to serve pages over port 80', :retry => 5, :retry_wait => 10 do
      shell('curl localhost:80', :acceptable_exit_codes => 7)
    end
  end
end
