
class redmine {

  include redmine::params
  include redmine::packages
  include redmine::rbenv
  include redmine::install
  include redmine::run_install
}

class redmine::params(
  $username = 'redmine',
  $appname = 'redmine',
  $password = 'vagrant',
  $db_adapter = "mysql2",
  $db_host = "localhost",
  $db_port = "3306",
  $db_username = "redmine",
  $db_passwd = "dummy",
  $db_name = "redmine",
  $version = "2.3.2") {

    #$username     = $username
    #$appname      = $appname
    #$password     = $password
    #$db_adapter   = $db_adapter
    #$db_host      = $db_host
    #$db_port      = $db_port
    #$db_username  = $db_username
    #$db_passwd    = $db_passwd
    #$db_name      = $db_name
    #$version      = $version
  $homedir = "/home/${username}"
  $destdir = "${homedir}/redmine-${version}"

}

class redmine::packages {
  package {
  "ruby1.9.1": ensure => present;
  "puppet": ensure => present;
  "bundler": ensure => present;
  "libmysqlclient-dev": ensure => present;
  "libmagickwand-dev": ensure => present;
  "imagemagick": ensure => present;
  "supervisor": ensure => present;
  }
}

class redmine::rbenv {
  Class["redmine::params"] -> Class["redmine::rbenv"]
  Class["redmine::packages"] -> Class["redmine::rbenv"]

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
  Class["redmine::rbenv"] -> Class["redmine::install"]

  # global
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

  $path = ["${rbenv_root}/bin", "${rbenv_root}/shims", "/usr/local/bin", "/bin", "/usr/bin"]

  Exec {
    cwd         => "$destdir",
    user        => $username,
    path        => $path
  }

  File {
    owner       => $username,
    group       => $username,
    mode        => 755
  }

  exec { "redmine::install::download ${version}":
    command   => "curl -L https://github.com/redmine/redmine/archive/${version}.tar.gz -o redmine-${version}.tar.gz",
    cwd       => "${homedir}",
    unless    => "test -e redmine-${version}.tar.gz"
  }

  exec { "redmine::install::extract ${version}":
    user      => "${username}",
    cwd       => "${homedir}",
    require   => Exec["redmine::install::download ${version}"],
    command   => "tar -xzvf redmine-${version}.tar.gz",
    unless    => "test -d $destdir"
  }

  file { "${destdir}/config/database.yml":
    ensure    => "present",
    content   => template("redmine/database.erb"),
    require   => Exec["redmine::install::extract ${version}"]
  }

  exec { "redmine::add::gems ${version}":
    require   => Exec["redmine::install::extract ${version}"],
    unless    => "grep -q puma Gemfile",
    command   => "echo >> Gemfile ; echo '# Added by puppet/redmine from Gnuside' >> Gemfile ; echo \"gem 'puma'\" >> Gemfile"
  }

  exec { "redmine::install::bundle ${version}":
    require   => [
      Exec["redmine::add::gems ${version}"],
      File["${destdir}/config/database.yml"]
    ],
    command   => "bundle install --without development test --path vendor/bundle"
  }

  exec { "redmine::install::secret":
    require     => [
      File[
        "$destdir/tmp/pdf","$destdir/files",
        "$destdir/public/plugin_assets",
        "$destdir/log"
      ],
      Exec["redmine::install::bundle ${version}"]
    ],
    unless      => "test -e ${destdir}/config/initializers/secret_token.rb",
    command     => "bundle exec rake generate_secret_token"
  }

  exec { "redmine::install::db_migrate":
    require     => Exec["redmine::install::secret"],
    environment => ["RAILS_ENV=production"],
    command     => "bundle exec rake db:migrate"
  }

  exec { "redmine::install::db_default_fill":
    require     => Exec["redmine::install::db_migrate"],
    environment => ["RAILS_ENV=production", "REDMINE_LANG=fr"],
    command     => "bundle exec rake redmine:load_default_data"
  }

  file { "$destdir/tmp":
    require     => Exec["redmine::install::extract ${version}"],
    ensure      => 'directory'
  }
  file { "$destdir/tmp/pdf":
    require     => File["$destdir/tmp"],
    ensure      => 'directory'
  }
  file { "$destdir/files":
    require     => Exec["redmine::install::extract ${version}"],
    ensure      => 'directory'
  }
  file { "$destdir/public":
    require     => Exec["redmine::install::extract ${version}"],
    ensure      => 'directory'
  }
  file { "$destdir/public/plugin_assets":
    require     => Exec["redmine::install::extract ${version}"],
    ensure      => 'directory'
  }
  file { "$destdir/log":
    require     => Exec["redmine::install::extract ${version}"],
    ensure      => 'directory'
  }
}

class redmine::run_install {
  Class["redmine::install"] -> Class["redmine::run_install"]


  $home         = $redmine::params::homedir
  $destdir      = $redmine::params::destdir
  $username     = $redmine::params::username

  $rbenv_root = "${home}/.rbenv"

  $path = ["${rbenv_root}/bin", "${rbenv_root}/shims", "${home}/bin", "/usr/local/bin", "/bin", "/usr/bin"]

  Exec {
    path      => $path
  }

  file {"${home}/bin":
    ensure    => 'directory'
  }

  file { "/etc/supervisor/conf.d/redmine.conf":
    ensure    => 'present',
    content   => template("redmine/supervisord-redmine.erb"),
    require   => File["${home}/bin/init-net-redmine.sh"]
  }

  file { "${home}/bin/init-net-redmine.sh":
    ensure    => 'present',
    content   => template("redmine/init-net.erb"),
    mode      => 755,
    require   => File["${home}/bin"]
  }

  exec { "redmine::run_install::supervisor restart":
    command   => "/etc/init.d/supervisor stop; /etc/init.d/supervisor start",
    require   => File[
      "${home}/bin/init-net-redmine.sh",
      "/etc/supervisor/conf.d/redmine.conf"
    ]
  }
}


class redmine::plugin_gitolite {
  Class["redmine::params"] -> Class["redmine::plugin_gitolite"]
  Class["redmine::run_install"] -> Class["redmine::plugin_gitolite"]
  Class["gitolite"] -> Class["redmine::plugin_gitolite"]

  $home         = $redmine::params::homedir
  $destdir      = $redmine::params::destdir
  $username     = $redmine::params::username

  $rbenv_root = "${home}/.rbenv"

  $path = ["${rbenv_root}/bin", "${rbenv_root}/shims", "${home}/bin", "/usr/local/bin", "/bin", "/usr/bin"]

  Exec {
    path        => $path,
    cwd         => "$destdir",
    user        => "$username",
    environment => ["RAILS_ENV=production"]
  }

  exec { "redmine::plugin_gitolite clone redmine_git_hosting":
    cwd         => "${destdir}/plugins",
    command     => "git clone https://github.com/jbox-web/redmine_git_hosting.git",
    unless      => "test -d redmine_git_hosting"
  }

  exec { "redmine::plugin_gitolite clone redmine_plugin_views_revisions":
    cwd         => "${destdir}/plugins",
    command     => "git clone https://github.com/jbox-web/redmine_plugin_views_revisions.git",
    unless      => "test -d redmine_plugin_views_revisions"
  }

  exec { "redmine::plugin_gitolite bundle install":
    command     => "bundle install",
    require     => Exec[
      "redmine::plugin_gitolite clone redmine_git_hosting",
      "redmine::plugin_gitolite clone redmine_plugin_views_revisions"
    ]
  }

  exec { "redmine::plugin_gitolite redmine:plugins:migrate":
    command     => "bundle exec rake redmine:plugins:migrate",
    require     => Exec["redmine::plugin_gitolite bundle install"]
  }

  exec { "redmine::plugin_gitolite redmine:plugins:process_version_change":
    command     => "bundle exec rake redmine:plugins:process_version_change",
    require     => Exec["redmine::plugin_gitolite redmine:plugins:migrate"]
  }

  exec { "redmine::plugin_gitolite supervisor restart":
    user        => "root",
    command     => "/etc/init.d/supervisor stop; /etc/init.d/supervisor start",
    require     => Exec["redmine::plugin_gitolite redmine:plugins:process_version_change"]
  }

  file { "${home}/.ssh":
    ensure      => "directory"
  }

  exec { "redmine::plugin_gitolite ssh-keygen":
    unless      => "test -e ${home}/.ssh/redmine_gitolite_admin_id_rsa",
    command     => "ssh-keygen -N '' -f ~/.ssh/redmine_gitolite_admin_id_rsa",
    require     => File["${home}/.ssh"]
  }

  exec { "redmine::plugin_gitolite gitolite gets ssh key":
    unless      => "TODO",
    command     => "cat ${home}/.ssh/redmine_gitolite_admin_id_rsa.pub >> ",
    require     => Exec["redmine::plugin_gitolite ssh-keygen"],
    user        => "gitolite" # correct that by an argument...
  }

}

