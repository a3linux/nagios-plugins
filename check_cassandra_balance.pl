#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-04 01:52:54 +0000 (Mon, 04 Nov 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#  

$DESCRIPTION = "Nagios Plugin to check the balance of ownership of tokens across nodes

Uses nodetool's status command to find token % across all nodes and alerts if the largest difference is greater than warning/critical thresholds. Returns perfdata of the max imbalance % for graphing.

Can specify a remote host and port otherwise it checks the local node's stats (for calling over NRPE on each Cassandra node)

Written and tested against Cassandra 2.0, DataStax Community Edition";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Cassandra;

my $default_warning  = 5;
my $default_critical = 10;

$warning  = $default_warning;
$critical = $default_critical;

%options = (
    %nodetool_options,
    "w|warning=s"      => [ \$warning,      "Warning  threshold max % difference (inclusive. Default: $default_warning)"  ],
    "c|critical=s"     => [ \$critical,     "Critical threshold max % difference (inclusive. Default: $default_critical)" ],
);

@usage_order = qw/nodetool host port user password warning critical/;
get_options();

($nodetool, $host, $port, $user, $password) = validate_nodetool_options($nodetool, $host, $port, $user, $password);
validate_thresholds(undef, undef, { "simple" => "upper", "integer" => 0, "positive" => 1, "max" => "100" });

vlog2;
set_timeout();

$status = "OK";

my $options = nodetool_options($host, $port, $user, $password);
my $cmd     = "${nodetool} ${options}status";

vlog2 "fetching cluster nodes information";
my @output = cmd($cmd);
#               name                  %    rack
my @max_node = ("uninitialized_node", 0,   "uninitialized_rack");
my @min_node = ("uninitialized_node", 100, "uninitialized_rack");
foreach(@output){
    if($_ =~ $nodetool_status_header_regex){
       next;
    }
    if(/^[^\s]+\s+([^\s]+)\s+[^\s]+(?:\s+[A-Za-z][A-Za-z])?\s+[^\s]+\s+(\d+(?:\.\d+)?)\%\s+[^\s]+\s+([^\s]+)/){
        my $node       = $1;
        my $percentage = $2;
        my $rack       = $3;
        if($percentage > $max_node[1]){
            @max_node = ($node, $percentage, $rack);
        }
        if($percentage < $min_node[1]){
            @min_node = ($node, $percentage, $rack);
        }
    } else {
        die_nodetool_unrecognized_output($_);
    }
}

my $max_diff_percentage = sprintf("%.2f", $max_node[1] - $min_node[1]);

$msg = "$max_diff_percentage% max imbalance between cassandra nodes"; 
check_thresholds($max_diff_percentage);
$msg .= ", max node: $max_node[1]% $max_node[0] ($max_node[2]), min node: $min_node[1]% $min_node[0] ($min_node[2])" if $verbose;
$msg .= " | 'max_%_imbalance'=$max_diff_percentage%";
msg_perf_thresholds();

vlog2;
quit $status, $msg;
