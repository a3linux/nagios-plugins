#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-13 19:32:32 +0100 (Sun, 13 Oct 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#  

# TODO: check if I can rewrite a version of this via API

$DESCRIPTION = "Nagios Plugin to check the number of available cassandra nodes and raise warning/critical on down nodes.

Uses nodetool's status command to determine how many downed nodes there are to compare against the warning/critical thresholds, also returns perfdata for graphing the node counts and states.

Can specify a remote host and port otherwise it checks the local node's stats (for calling over NRPE on each Cassandra node)

Written and tested against Cassandra 2.0, DataStax Community Edition";

$VERSION = "0.3";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;
use HariSekhon::Cassandra;

my $default_warning  = 0;
my $default_critical = 1;

$warning  = $default_warning;
$critical = $default_critical;

%options = (
    %nodetool_options,
    "w|warning=s"      => [ \$warning,      "Warning  threshold max (inclusive. Default: $default_warning)"  ],
    "c|critical=s"     => [ \$critical,     "Critical threshold max (inclusive. Default: $default_critical)" ],
);

@usage_order = qw/nodetool host port user password warning critical/;
get_options();

($nodetool, $host, $port, $user, $password) = validate_nodetool_options($nodetool, $host, $port, $user, $password);
validate_thresholds(undef, undef, { "simple" => "upper", "integer" => 1, "positive" => 1});

vlog2;
set_timeout();

$status = "OK";

my $options = nodetool_options($host, $port, $user, $password);
my $cmd     = "${nodetool} ${options}status";

vlog2 "fetching cluster nodes information";
my @output = cmd($cmd);

my $up_nodes      = 0;
my $down_nodes    = 0;
my $normal_nodes  = 0;
my $leaving_nodes = 0;
my $joining_nodes = 0;
my $moving_nodes  = 0;

sub parse_state ($) {
    if(/^[UD][NLJM]\s+($host_regex)/){
        if(/^.N/){
            $normal_nodes++;
        } elsif(/^.L/){
            $leaving_nodes++;
        } elsif(/^.J/){
            $joining_nodes++;
        } elsif(/^.M/){
            $moving_nodes++;
        } else {
            quit "UNKNOWN", "unrecognized second column for node status, $nagios_plugins_support_msg";
        }
    }
}


foreach(@output){
    if($_ =~ $nodetool_status_header_regex){
       next;
    }
    # Don't know what remote JMX auth failure looks like yet so will go critical on any user/password related message returned assuming that's an auth failure
    if($_ =~ $nodetool_errors_regex){
        quit "CRITICAL", $_;
    }
    if(/^U/){
        $up_nodes++;
        parse_state($_);
    } elsif(/^D/){
        $down_nodes++;
        parse_state($_);
    } else {
        die_nodetool_unrecognized_output($_);
    }
}

vlog2 "checking node counts";
unless( ($up_nodes + $down_nodes ) == ($normal_nodes + $leaving_nodes + $joining_nodes + $moving_nodes)){
    quit "UNKNOWN", "live+down node counts vs (normal/leaving/joining/moving) nodes are not equal, investigation required";
}

$msg = "$up_nodes nodes up, $down_nodes down";
check_thresholds($down_nodes);
$msg .= ", node states: $normal_nodes normal, $leaving_nodes leaving, $joining_nodes joining, $moving_nodes moving | up_nodes=$up_nodes down_nodes=$down_nodes";
msg_perf_thresholds();
$msg .= " normal_nodes=$normal_nodes leaving_nodes=$leaving_nodes joining_nodes=$joining_nodes moving_nodes=$moving_nodes";

vlog2;
quit $status, $msg;
