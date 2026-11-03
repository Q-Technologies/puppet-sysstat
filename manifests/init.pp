# == Class: sysstat
#
# A module to manage the sysstat configuration
#
# @param [String] package The name of the sysstat package to install.
# @param [String] cron_path The path of the sysstat crontab managed by this class.
# @param [String] cron_path2 The path of the Debian cron.daily entry to remove.
# @param [String] conf_path The path of the sysstat configuration file to manage.
# @param [String] sa1_path The path to the sa1 data collection command.
# @param [String] sa2_path The path to the sa2 summary generation command.
# @param [String] sa2_hour The hour at which sa2 generates the daily summary.
# @param [String] sa2_minute The minute at which sa2 generates the daily summary.
# @param [String] sa_dir The directory where sysstat activity data is stored.
# @param [String] sa1_options Options passed to sa1 during data collection.
# @param [Integer] interval Default collection interval in minutes, used by sa1_interval.
# @param [Integer] sa1_interval How often sa1 collects data, in minutes.
# @param [Integer] duration Default collection duration in minutes, used by sa1_duration.
# @param [Integer] sa1_duration Duration of each sa1 invocation, in minutes.
# @param [Integer] samples Default number of samples per invocation, used by sa1_samples.
# @param [Integer] sa1_samples Number of samples collected by each sa1 invocation.
# @param [String] sa2_options Options passed to sa2 when generating the daily summary.
# @param [Integer] history Number of days to retain sysstat activity data.
# @param [Integer] compressafter Age in days after which activity files are compressed.
# @param [String] sadc_options Options passed to the sadc data collector.
# @param [String] zip The compression program used for activity files.
# @param [String] generate_summary Whether to generate the daily summary ('yes' or 'no').
# @param [String] disable Whether to disable collection and remove its schedule ('yes' or 'no').
# @param [Integer] sa2_delay_range Maximum random delay before sa2 runs, in seconds.
# @param [String] sa_umask The umask used for sysstat activity and report files.
class sysstat (
  String $package,
  String $cron_path,
  String $cron_path2,
  String $conf_path,
  String $sa1_path,
  String $sa2_path,
  String $sa2_hour,
  String $sa2_minute,
  String $sa_dir,

  String    $sa1_options      = '-S ALL',
  Integer   $interval         = 2,
  Integer   $sa1_interval     = $interval,
  Integer   $duration         = 2,
  Integer   $sa1_duration     = $duration,
  Integer   $samples          = 1,
  Integer   $sa1_samples      = $samples,
  String    $sa2_options      = '-A',
  Integer   $history          = 10,
  Integer   $compressafter    = 31,
  String    $sadc_options     = '-S DISK',
  String    $zip              = 'bzip2',
  String    $generate_summary = 'yes',
  String    $disable          = 'no',
  Integer   $sa2_delay_range  = 0,
  String    $sa_umask         = '0022',
) {
  # Convert duration to seconds
  $sa1_duration_seconds = $sa1_duration * 60 - 1

  if $generate_summary == 'yes' and $disable != 'yes' {
    $svc_summary_ensure = true
  } else {
    $svc_summary_ensure = false
  }

  if $disable == 'yes' {
    $file_ensure        = 'absent'
    $cron_ensure        = 'absent'
    $svc_collect_ensure = false
  } else {
    $file_ensure        = 'file'
    $cron_ensure        = 'present'
    $svc_collect_ensure = true
  }

  if ($facts['os']['family'] == 'RedHat' and Float($facts['os']['release']['major']) >= 8.0)
  or ($facts['os']['distro'] and $facts['os']['distro']['id'] == 'Debian' and Float($facts['os']['release']['major']) >= 11.0)
  or ($facts['os']['distro'] and $facts['os']['distro']['id'] == 'Ubuntu' and Float($facts['os']['release']['major']) >= 22.04) {
    $use_systemd_timers = true
  } else {
    $use_systemd_timers = false
  }

  case $facts['os']['family'] {
    'AIX': {
      cron { 'sa1_path_weekday':
        ensure  => 'absent',
        command => "${sa1_path} 1200 3 &",
        user    => 'adm',
        hour    => ['8-17'],
        minute  => [0],
        weekday => ['1-5'],
      }
      cron { 'sa1_path_weekday_after_hours':
        ensure  => 'absent',
        command => "${sa1_path} &",
        user    => 'adm',
        minute  => [0],
        hour    => ['18-7'],
        weekday => ['1-5'],
      }
      cron { 'sa1_path_weekend':
        ensure  => 'absent',
        command => "${sa1_path} &",
        user    => 'adm',
        minute  => [0],
        weekday => [0,6],
      }
      cron { 'sa2_path_weekday_after_hours':
        ensure  => $cron_ensure,
        command => "${sa2_path} -s 8:00 -e 18:01 -i 3600 -ubcwyaqvm &",
        user    => 'adm',
        minute  => [5],
        hour    => [18],
        weekday => ['1-5'],
      }
      cron { 'sa1_daily_5_mins':
        ensure  => $cron_ensure,
        command => "${sa1_path} &",
        user    => 'adm',
        minute  => [0,5,10,15,20,25,30,35,40,45,50,55],
        weekday => ['0-6'],
      }
    }
    default: {
      package { $package:
        ensure => 'installed',
      }

      if $use_systemd_timers {
        file { [
            '/etc/systemd/system/sysstat-summary.timer.d',
            '/etc/systemd/system/sysstat-collect.timer.d',
            '/etc/systemd/system/sysstat-summary.service.d',
            '/etc/systemd/system/sysstat-collect.service.d',
          ]:
            ensure => 'directory',
            mode   => '0755',
            group  => 'root',
            owner  => 'root',
        }
        exec { 'systemctl daemon-reload':
          command     => 'systemctl daemon-reload',
          path        => ['/bin','/usr/bin','/sbin','/usr/sbin'],
          refreshonly => true,
          subscribe   => Package[$package],
        }
        file { '/etc/systemd/system/sysstat-collect.timer.d/override.conf':
          ensure  => file,
          content => epp('sysstat/sysstat_collect.timer.override.epp', {
            sa1_interval => $sa1_interval,
          }),
          notify  => Exec['systemctl daemon-reload'],
        }
        file { '/etc/systemd/system/sysstat-summary.timer.d/override.conf':
          ensure  => file,
          content => epp('sysstat/sysstat_summary.timer.override.epp', {
            sa2_minute => $sa2_minute,
            sa2_hour   => $sa2_hour,
          }),
          notify  => Exec['systemctl daemon-reload'],
        }
        file { '/etc/systemd/system/sysstat-collect.service.d/override.conf':
          ensure  => file,
          content => epp('sysstat/sysstat_collect.service.override.epp', {
            sa1_path             => $sa1_path,
            sa1_duration_seconds => $sa1_duration_seconds,
            sa1_samples          => $sa1_samples,
          }),
          notify  => Exec['systemctl daemon-reload'],
        }
        file { '/etc/systemd/system/sysstat-summary.service.d/override.conf':
          ensure  => file,
          content => epp('sysstat/sysstat_summary.service.override.epp', {
            sa2_path    => $sa2_path,
            sa2_options => $sa2_options,
          }),
          notify  => Exec['systemctl daemon-reload'],
        }
        service { 'sysstat-collect.timer':
          ensure  => $svc_collect_ensure,
          enable  => $svc_collect_ensure,
          require => Package[$package],
        }
        service { 'sysstat-summary.timer':
          ensure  => $svc_summary_ensure,
          enable  => $svc_summary_ensure,
          require => Package[$package],
        }
      } else {
        file { $cron_path:
          ensure  => $file_ensure,
          content => epp('sysstat/crontab.epp', {
            sa1_path             => $sa1_path,
            sa1_options          => $sa1_options,
            sa1_interval         => $sa1_interval,
            sa1_duration         => $sa1_duration,
            sa1_duration_seconds => $sa1_duration_seconds,
            sa1_samples          => $sa1_samples,
            sa2_path             => $sa2_path,
            sa2_options          => $sa2_options,
            sa2_minute           => $sa2_minute,
            sa2_hour             => $sa2_hour,
            generate_summary     => $generate_summary,
          }),
        }
      }

      file { $conf_path:
        ensure  => file,
        content => epp('sysstat/sysconfig.epp', {
          history         => $history,
          compressafter   => $compressafter,
          sa_dir          => $sa_dir,
          sa2_delay_range => $sa2_delay_range,
          sadc_options    => $sadc_options,
          sa_umask        => $sa_umask,
          zip             => $zip,
        }),
        require => Package[$package],
      }

      file { $sa_dir:
        ensure => directory,
        owner  => 'root',
        group  => 'root',
      }

      # With this module we disable the Debian uniqueness regardless of whether
      # the module is disabled or not
      if $facts['os']['family'] == 'Debian' {
        service { 'sysstat':
          ensure => false,
          enable => ($use_systemd_timers and $svc_collect_ensure),
        }
        file { $cron_path2:
          ensure => absent,
        }
      }
    }
  }
}
