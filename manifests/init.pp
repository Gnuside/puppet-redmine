
# install apache
# ensure it runs
# enable mod_rewrite
# enable mod_php5

## CONFIG

class redmine {
}

$rep_name = "project";

define redmine::install (
  $root,
  $db_name,
  $version = "2.3.2"
) {
  $data_folder = "/vagrant/data/redmine"
  $src_path = "/usr/local/src"
  $archive_name = "redmine-${version}.tar.gz"
  $archive_url = "http://rubyforge.org/frs/download.php/77023/${archive_name}"
  $redmine_path = "${root}/redmine/${version}"
  $archive_tmp = "${src_path}/${archive_name}"

  file {["${root}/redmine"]:
    ensure => 'directory',
    owner => "www-data",
    group => "www-data",
    mode => 0644
  }

  exec { "redmine::install::download ${version}":
    require => File["${root}"],
    unless => "test -f ${archive_tmp}",
    command => "wget '${archive_url}' -O '${archive_tmp}' || \
                (rm '${archive_tmp}' && false)",
    user => "root",
    group => "root"
  }

  exec { "redmine::install::extract ${version} to ${redmine_path}":
    unless  => "test -d ${redmine_path}",
    cwd     => "${src_path}",
    command => "tar -xzf ${archive_tmp} && mv ${src_path}/redmine-${version} ${redmine_path} && chown -R www-data:www-data ${redmine_path} && find ${redmine_path} -type f -exec chmod 644 {} \; && find ${redmine_path} -type d -exec chmod 755 {} \;",
    require => [
      Exec["redmine::install::download ${version}"],
      File["${root}/redmine"]
    ]
  }

  file { "${redmine_path}":
    ensure => 'directory',
    owner => "www-data",
    group => "www-data",
    #owner => "root",
    #group => "root",
    mode => 644,
    require => Exec["redmine::install::extract ${version} to ${redmine_path}"]
  }

  file { ["${root}/${rep_name}", "${root}/${rep_name}/documents", "${root}/${rep_name}/configuration"]:
    ensure    => 'directory',
    owner     => "www-data",
    group     => "www-data",
    mode      => 0644
  }

  file { "${root}/${rep_name}/configuration/database.yml":
    ensure    => present,
    owner     => "www-data",
    group     => "www-data",
    mode      => 0400,
    content => template("${redmine_path}/config/database.yml.example"),
    require   => File["${root}/${rep_name}/configuration"]
  }

  file { "${root}/${rep_name}/root":
    ensure    => "link",
    target    => "${redmine_path}",
    owner     => "www-data",
    group     => "www-data",
    mode      => 0644,
    require   => File["${redmine_path}", "${root}/${rep_name}", "${root}/${rep_name}/configuration/database.yml"]
  }

  file { "${root}/${rep_name}/root/config/database.yml":
    ensure    => "link",
    target    => "${root}/${rep_name}/configuration/database.yml",
    owner     => "www-data",
    group     => "www-data",
    mode      => 0644,
    require   => File["${root}/${rep_name}/root", "${redmine_path}", "${root}/${rep_name}/configuration/database.yml"]
  }

}

define redmine::pre_configure (
  $db_root_pwd,
  $http_root,
  $db_name,
  $db_user,
  $db_pswd
) {
  # this "function" allow to check and do what must be done previously to configuration
  $data_folder = "/vagrant/data/redmine"

}

define redmine::configure (
  $http_root,
  $db_kind,
  $db_name,
  $db_user,
  $db_pswd
) {
  $data_folder = "/vagrant/data/redmine"

  if $db_kind == 'mysql' {
    $sql_command = "CREATE DATABASE ${db_name} CHARACTER SET utf8;
CREATE USER '${db_user}'@'localhost' IDENTIFIED BY '${db_pswd}';
GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'localhost';"
    $db_config =
    "# Configuration made by puppet-redmine scripts
      production:
        adapter: mysql
        database: ${db_name}
        host: localhost
        username: ${db_user}
        password: ${db_pswd}"
    exec { "redmin::configuration::create db + db_user":
      command   => "mysql --user=root --password=${db_root_pwd} --execute='${sql_command}'",
    }

    exec {
      cwd       => "${http_root}",
      command   => "echo $db_config > ../configuration/database.yml"
    }
  }

  package { "gem":
    ensure  => installed
  }

  exec { "redmine::configure::dependencies installation ":
    cwd     => "${http_root}",
    command => "gem install bundler && bundle install --without development test",
    require => Package["gem"]
  }

}
