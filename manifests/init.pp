# Class: postgres
#
# This module manages postgres
#
# Parameters:
#
# Actions:
#
# Requires:
#
# Sample Usage: see postgres/README.markdown
#
# [Remember: No empty lines between comments and class definition]
class postgres($version = '8.4', $password = '') {
  # Handle version specified in site.pp (or default to postgresql)
  $postgres_client = "postgresql-client-${version}"
  $postgres_server = "postgresql-${version}"

  case $::operatingsystem {
    debian, ubuntu: {
      class {
        'postgres::debian' :
          version => $version;
      }

      $data_path = "/var/lib/postgresql/${version}"
    }
    default: {
      package {
        [$postgres_client, $postgres_server]:
          ensure => installed,
      }

      $data_path = "/var/lib/pgsql/data"

      file { ["/var/lib/pgsql", "/var/lib/pgsql/data"]:
        ensure => directory,
        recurse => true,
        owner => postgres,
        group => postgres,
        mode	=> 700,
        require => User['postgres']
      }
    }
  }

  user { 'postgres':
    ensure     => present
  }

}


# Initialize the database with the password password.
define postgres::initdb() {
  case $::operatingsystem {
    debian, ubuntu: {
      exec { 'InitDB':
        command => "echo ok",
        require => Package[$postgres::postgres_server]
      }
    }
    default: {
      if $postgres::password == "" {
        exec {
          'InitDB':
            command => "/bin/su postgres -c \"/usr/bin/initdb ${postgres::data_path} -E UTF8\"",
            require => [Package[$postgres::postgres_server], File[$postgres::data_path]],
            unless  => "/usr/bin/test -e ${postgres::data_path}/PG_VERSION",
        }
      } else {
        exec {
          'InitDB':
            command => "echo \"${postgres::password}\" > /tmp/ps && /bin/su  postgres -c \"/usr/bin/initdb ${postgres::data_path} --auth='password' --pwfile=/tmp/ps -E UTF8 \" && rm -rf /tmp/ps",
            require => [Package[$postgres::postgres_server], File[$postgres::data_path]],
            unless  => "/usr/bin/test -e ${postgres::data_path}/PG_VERSION ",
        }
      }
    }
  }
}

# Start the service if not running
define postgres::enable {
  service { postgresql:
    name      => "${postgres::postgres_server}",
    ensure    => running,
    enable    => true,
    hasstatus => true,
    require   => Exec["InitDB"],
  }
}


# Postgres host based authentication
define postgres::hba ($password="",$allowedrules){
  file { "${postgres::data_path}/pg_hba.conf":
    content   => template("postgres/pg_hba.conf.erb"),
    owner     => "root",
    group     => "root",
    notify    => Service["postgresql"],
    # require => File["/var/lib/pgsql/.order"],
    require   => Exec["InitDB"],
  }
}

define postgres::config ($listen="localhost")  {
  file {"${postgres::data_path}/postgresql.conf":
    content => template("postgres/postgresql.conf.erb"),
    owner   => postgres,
    group   => postgres,
    notify  => Service["postgresql"],
    # require => File["/var/lib/pgsql/.order"],
    require => Exec["InitDB"],
  }
}

# Base SQL exec
define sqlexec($username, $password, $database, $sql, $sqlcheck) {
  case $::operatingsystem {
    debian, ubuntu: {
      exec{ "sudo -u ${username} psql $database -c \"${sql}\" >> /var/lib/puppet/log/postgresql.sql.log 2>&1 && /bin/sleep 5":
        timeout     => 600,
        unless      => "sudo -u ${username} psql $database -c $sqlcheck",
        require     =>  [User['postgres'],Service[postgresql]],
      }
    }
    default: {
      if $password == "" {
        exec{ "psql -h localhost --username=${username} $database -c \"${sql}\" >> /var/lib/puppet/log/postgresql.sql.log 2>&1 && /bin/sleep 5":
          timeout     => 600,
          unless      => "psql -U $username $database -c $sqlcheck",
          require     =>  [User['postgres'],Service[postgresql]],
        }
      } else {
        exec{ "psql -h localhost --username=${username} $database -c \"${sql}\" >> /var/lib/puppet/log/postgresql.sql.log 2>&1 && /bin/sleep 5":
          environment => "PGPASSWORD=${password}",
          timeout     => 600,
          unless      => "psql -U $username $database -c $sqlcheck",
          require     =>  [User['postgres'],Service[postgresql]],
        }
      }
    }
  }
}

# Create a Postgres user
define postgres::createuser($passwd) {
  sqlexec{ createuser:
    password => $postgres::password,
    username => "postgres",
    database => "postgres",
    sql      => "CREATE ROLE ${name} WITH LOGIN PASSWORD '${passwd}';",
    sqlcheck => "\"SELECT usename FROM pg_user WHERE usename = '${name}'\" | grep ${name}",
    require  =>  Service[postgresql],
  }
}

# Create a Postgres db
define postgres::createdb($owner) {
  sqlexec{ $name:
    password => $postgres::password,
    username => "postgres",
    database => "postgres",
    sql      => "CREATE DATABASE $name WITH OWNER = $owner TEMPLATE = template0 ENCODING = 'UTF8';",
    sqlcheck => "\"SELECT datname FROM pg_database WHERE datname ='$name'\" | grep $name",
    require  => Service[postgresql],
  }
}
