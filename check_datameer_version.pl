#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-27 20:07:10 +0000 (Wed, 27 Nov 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# http://documentation.datameer.com/documentation/display/DAS21/Accessing+Datameer+Using+the+REST+API

$DESCRIPTION = "Nagios Plugin to check the Datameer version using the Datameer Rest API

Tested against Datameer 2.1.x.x";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use JSON::XS;
use LWP::UserAgent;
use Time::Local;

my $default_port = 8080;
$port = $default_port;

my $expected;

%options = (
    "H|host=s"         => [ \$host,         "Datameer server" ],
    "P|port=s"         => [ \$port,         "Datameer port (default: $default_port)" ],
    "u|user=s"         => [ \$user,         "User to connect with (\$DATAMEER_USER)" ],
    "p|password=s"     => [ \$password,     "Password to connect with (\$DATAMEER_PASSWORD)" ],
    "e|expected=s"     => [ \$expected,     "Expected version regex, raises CRITICAL if not matching, optional" ],
);

@usage_order = qw/host port user password warning critical/;

if(defined($ENV{"DATAMEER_USER"})){
    $user = $ENV{"DATAMEER_USER"};
}
if(defined($ENV{"DATAMEER_PASSWORD"})){
    $password = $ENV{"DATAMEER_PASSWORD"};
}

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
$expected   = validate_regex($expected, "expected version") if defined($expected);

my $url = "http://$host:$port/rest/license-details";

vlog2;
set_timeout();

$status = "OK";

my $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon $progname $main::VERSION");
$ua->credentials($host, '', $user, $password);

# Lifted from check_cloudera_manager_metrics.pl TODO: move to lib
#my $content = get $url;
vlog2 "querying $url";
my $req = HTTP::Request->new('GET',$url);
$req->authorization_basic($user, $password);
my $response = $ua->request($req);
my $content  = $response->content;
chomp $content;
vlog3 "returned HTML:\n\n" . ( $content ? $content : "<blank>" ) . "\n";
vlog2 "http code: " . $response->code;
vlog2 "message: " . $response->message;

unless($response->code eq "200"){
    quit "UNKNOWN", $response->code . " " . $response->message;
}

my $json;
try{
    $json = decode_json $content;
};
catch{
    quit "CRITICAL", "invalid json returned by '$host:$port'";
};

unless(defined($json->{"ProductVersion"})){
    quit "UNKNOWN", "ProductVersion was not defined in json output returned from Datameer server. Format may have changed. $nagios_plugins_support_msg";
}
my $datameer_version = $json->{"ProductVersion"};

$datameer_version =~ /^\d+(\.\d+)+$/ or quit "UNKNOWN", "unrecognized Datameer version, expecting x.y.z.. format. Format may have changed. $nagios_plugins_support_msg";

$msg = "Datameer version is '$datameer_version'";
if(defined($expected) and $datameer_version !~ /^$expected$/){
    critical;
    $msg .= " (expected: $expected)";
}

vlog2 if is_ok;
quit $status, $msg;
