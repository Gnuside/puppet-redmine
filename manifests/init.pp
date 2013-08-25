
class redmine {
  include redmine::packages
  include redmine::rbenv
  include redmine::install
}

class redmine::params {
  $username = 'redmine'
  $appname = 'redmine'
  $password = 'vagrant'
  $repository_url = "git://github.com/Gnuside/barcamp-garden.git"
  $version = "1.4"
  $destdir = "/home/${username}/redmine-${version}"
}

class redmine::packages {
  package {
  "git": ensure => present;
  "ruby1.9.1": ensure => present;
  "puppet": ensure => present;
  "bundler": ensure => present;
  }
}

class redmine::rbenv {
  include redmine::params

  # global
  $app_name = $redmine::params::appname
  $destdir = $redmine::params::destdir
  $username = $redmine::params::username
  $home = "/home/${username}"

  # local
  $ruby_version = '1.9.3-debian'
  $rbenv_root = "${home}/.rbenv"

  $path = "${rbenv_root}/bin:${rbenv_root}/shims:/bin:/usr/bin"

  user { "${username}":
    # groups => $username,
    comment => 'This user was created by Puppet',
    ensure => 'present',
    managehome => 'true',
    home => $home,
    shell => '/bin/bash'
  }

  rbenv::install { "rbenv::install ${username}":
    user => $username,
    home => $home,
    # group => 'redmine',
    # root  => '/usr/share/rbenv',
    #require => File['/usr/share/rbenv']
    require => User[$username]
  }

  rbenv::plugin { "rbenv::plugin alternatives":
    plugin_name => 'alternatives',
    user        => $username,
    home        => $home,
    # root  => '/usr/share/rbenv',
    source      => "git://github.com/terceiro/rbenv-alternatives.git",
    require     => User[$username],
    before      => Exec["rbenv::compile ${username} ${ruby_version}"]
  }

  # FAKE RBENV COMMAND. THE RULE TITLE IS IMPORTANT & MUST NOT BE CHANGED.
  exec { "rbenv::compile ${username} ${ruby_version}":
    command     => 'rbenv alternatives',
    path        => $path,
    user        => $username,
    environment => [ "HOME=${home}" ],
    cwd         => $home,
    #before => Rbenv::Client['redmine']
    before      => [Exec["rbenv::global ${username} ${ruby_version}"],
                    Exec["rbenv::rehash ${username} ${ruby_version}"]],
    require     => Class['redmine::packages']
  }

  notice("redmine home ${destdir}")

  exec { "rbenv::rehash ${username} ${ruby_version}":
    command     => "rbenv rehash && rm -f ${rbenv_root}/.rehash",
    user        => $username,
    cwd         => $home,
    onlyif      => "[ -e '${rbenv_root}/.rehash' ]",
    environment => [ "HOME=${home}" ],
    path        => $path,
  }

  exec { "rbenv::global ${username} ${ruby_version}":
    command     => "rbenv global ${ruby_version}",
    user        => $username,
    cwd         => $home,
    environment => [ "HOME=${home}" ],
    path        => $path,
    before      => Exec["rbenv::rehash ${username} ${ruby_version}"],
    require     => Exec["rbenv::compile ${username} ${ruby_version}"]
  }
}

class redmine::install {
  include redmine::params
}

#FIXME: transform into a define
class redmine::plugin {
  include redmine::params
}

# FIXME install redmine/gitolite
