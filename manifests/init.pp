
class redmine {
  include redmine::packages
  include redmine::rbenv
  include redmine::install
}

class redmine::params {
  $username = 'redmine'
  $appname = 'redmine'
  $password = 'vagrant'
  $repository_url = "http://github.com/Gnuside/barcamp-garden"
  $version = "2.3.2"
  $homedir = "/home/${username}"
  $destdir = "${homedir}/redmine-${version}"
  $db_adapter = "mysql"
  $db_host = "localhost"
  $db_port = "" # default 3306
  $db_username = "${username}"
  $db_passwd = "dummy"
  $db_name = "redmine"

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

  $destdir      = $redmine::params::destdir
  $version      = $redmine::params::version
  $homedir      = $redmine::params::homedir
  $username     = $redmine::params::username
  $db_adapter   = $redmine::params::db_adapter
  $db_name      = $redmine::params::db_name
  $db_host      = $redmine::params::db_host
  $db_port      = $redmine::params::db_port
  $db_username  = $redmine::params::db_username
  $db_passwd    = $redmine::params::db_passwd

  $rbenv_root = "${homedir}/.rbenv"

  $path = ["${rbenv_root}/bin", "${rbenv_root}/shims", "/bin", "/usr/bin"]

  Exec {
    path => $path
  }

  exec { "redmine::install::download ${version}":
    user      => "${username}",
    command   => "curl -L https://github.com/redmine/redmine/archive/${version}.tar.gz -o redmine-${version}.tar.gz",
    cwd       => "${homedir}",
    path      => $path,
    unless    => "test -e redmine-${version}.tar.gz"
  }

  exec { "redmine::install::extract ${version}":
    user      => "${username}",
    cwd       => "${homedir}",
    path      => $path,
    require   => Exec["redmine::install::download ${version}"],
    command   => "tar -xzvf redmine-${version}.tar.gz"
  }

  file { "${destdir}/config/database.yml":
    ensure    => "present",
    content   => template("redmine/database.erb"),
    require   => Exec["redmine::install::extract ${version}"]
  }

  exec { "redmine::install::bundle ${version}":
    user      => "${username}",
    require   => [
      Exec["redmine::install::extract ${version}"],
      File["${destdir}/config/database.yml"],
      Class["redmine::rbenv"]
    ],
    path      => $path,
    cwd       => "${destdir}",
    command   => "bundle install --without development test --path vendor/bundle"
  }
}

#FIXME: transform into a define
class redmine::plugin {
  include redmine::params
}

# FIXME install redmine/gitolite
